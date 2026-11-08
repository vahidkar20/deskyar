#!/usr/bin/env bash
#
# Build vcpkg without touching the GitHub *release* CDN.
#
# ## Why this exists
#
# `lukka/run-vcpkg` clones the vcpkg repo and then runs `bootstrap-vcpkg`,
# which downloads a prebuilt `vcpkg` / `vcpkg.exe` from
# `github.com/microsoft/vcpkg-tool/releases/download/...`. That URL redirects
# to `objects.githubusercontent.com`, and during the 1.5.5 builds that host
# answered `504 Gateway Time-out` for over an hour - from the runners and from
# an independent machine. `github.com` itself was fine, and so was
# `codeload.github.com`, which serves the *source* archives.
#
# So: clone the ports repo at the pinned commit, and if the tool binary is not
# already there, fetch the tool's source archive (codeload) and build it with
# CMake. Same binary, different host, no release CDN involved.
#
# Everything the rest of the workflow needs is exported through GITHUB_ENV:
# VCPKG_ROOT for `build_android_deps.sh` and for the `vcpkg` crate in build.rs.
#
# Usage:
#   VCPKG_ROOT=... VCPKG_COMMIT_ID=... tools/setup-vcpkg.sh

set -euo pipefail

: "${VCPKG_ROOT:?VCPKG_ROOT must be set}"
: "${VCPKG_COMMIT_ID:?VCPKG_COMMIT_ID must be set}"

log() { echo "==> $*"; }

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) BIN="$VCPKG_ROOT/vcpkg.exe" ;;
  *) BIN="$VCPKG_ROOT/vcpkg" ;;
esac

# ---------------------------------------------------------------------------
# 1. The ports repository at the pinned commit.
# ---------------------------------------------------------------------------
if [ ! -d "$VCPKG_ROOT/.git" ]; then
  log "cloning vcpkg into $VCPKG_ROOT"
  mkdir -p "$VCPKG_ROOT"
  git clone --filter=blob:none --no-checkout \
    https://github.com/microsoft/vcpkg.git "$VCPKG_ROOT"
fi

if [ "$(git -C "$VCPKG_ROOT" rev-parse HEAD 2>/dev/null || echo none)" != "$VCPKG_COMMIT_ID" ]; then
  log "checking out $VCPKG_COMMIT_ID"
  # A shallow fetch of one commit is what the action did too; fall back to a
  # full fetch if the server refuses to serve an arbitrary sha.
  git -C "$VCPKG_ROOT" fetch --depth 1 origin "$VCPKG_COMMIT_ID" \
    || git -C "$VCPKG_ROOT" fetch origin
  git -C "$VCPKG_ROOT" checkout -f "$VCPKG_COMMIT_ID"
fi

# ---------------------------------------------------------------------------
# 2. Route every GitHub archive download through codeload.
#
# `github.com/<org>/<repo>/archive/<ref>` answers 504 or hangs for minutes on
# the build runners, while `codeload.github.com` - the host that actually
# serves those archives - is healthy. It is not only ports that use it:
# `vcpkg_find_acquire_program(MESON)` fetches meson's source from the same
# path, which is how the build died after the ports were already fixed.
#
# So the rewrite goes into `z_vcpkg_download_distfile`, the single function
# every download funnels through, rather than into `vcpkg_from_github`. Each
# portfile still verifies its own SHA512 afterwards, so a wrong byte anywhere
# fails loudly instead of silently producing a broken build.
# ---------------------------------------------------------------------------
vdd="$VCPKG_ROOT/scripts/cmake/vcpkg_download_distfile.cmake"
if [ -f "$vdd" ] && ! grep -q codeload.github.com "$vdd"; then
  py=""
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
      py="$candidate"
      break
    fi
  done
  if [ -n "$py" ]; then
    "$py" - "$vdd" <<'PY'
import sys
import pathlib

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
anchor = "    foreach(url IN LISTS arg_URLS)"
if anchor not in text:
    print("vcpkg_download_distfile: anchor not found")
    raise SystemExit(1)
inject = """    foreach(url IN LISTS arg_URLS)
        # NexDesk: github.com/<owner>/<repo>/archive/<ref> is unreachable from
        # CI, while codeload.github.com serves the very same archive.
        string(REGEX REPLACE
            "^https://github\\\\.com/([^/]+)/([^/]+)/archive/(.*)\\\\.tar\\\\.gz$"
            "https://codeload.github.com/\\\\1/\\\\2/tar.gz/\\\\3"
            url "${url}")
        string(REGEX REPLACE
            "^https://github\\\\.com/([^/]+)/([^/]+)/archive/(.*)\\\\.zip$"
            "https://codeload.github.com/\\\\1/\\\\2/zip/\\\\3"
            url "${url}")"""
path.write_text(text.replace(anchor, inject, 1), encoding="utf-8")
print("vcpkg_download_distfile: archives routed through codeload")
PY
    if grep -q codeload.github.com "$vdd"; then
      log "archive downloads routed through codeload.github.com"
    else
      log "WARNING: could not rewrite vcpkg_download_distfile"
    fi
  else
    log "WARNING: no python on PATH, cannot rewrite vcpkg download URLs"
  fi
fi

# ---------------------------------------------------------------------------
# 3. The tool binary, built from source when it is missing.
# ---------------------------------------------------------------------------
if [ -f "$BIN" ]; then
  log "vcpkg binary already present at $BIN"
else
  tag=$(sed -n 's/^VCPKG_TOOL_RELEASE_TAG=//p' \
    "$VCPKG_ROOT/scripts/vcpkg-tool-metadata.txt" | tr -d '\r' | tr -d '"')
  [ -n "$tag" ] || { echo "cannot read VCPKG_TOOL_RELEASE_TAG"; exit 1; }

  log "building vcpkg-tool $tag from source"
  work="$VCPKG_ROOT/buildtrees/_vcpkg"
  rm -rf "$work"
  mkdir -p "$work"

  curl -fsSL --retry 5 --retry-delay 3 \
    -o "$work/tool.zip" \
    "https://github.com/microsoft/vcpkg-tool/archive/refs/tags/$tag.zip"
  (cd "$work" && unzip -q tool.zip)

  src="$work/vcpkg-tool-$tag"
  [ -d "$src" ] || { echo "expected sources in $src"; ls -la "$work"; exit 1; }

  cmake -S "$src" -B "$work/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DVCPKG_DEVELOPMENT_WARNINGS=OFF
  cmake --build "$work/build" --config Release --parallel

  built=$(find "$work/build" -type f \( -name vcpkg -o -name vcpkg.exe \) | head -1)
  [ -n "$built" ] || { echo "vcpkg binary not found after build"; exit 1; }
  cp "$built" "$BIN"
  chmod +x "$BIN" 2>/dev/null || true
fi

"$BIN" version

# ---------------------------------------------------------------------------
# 4. Hand the paths to the following steps.
# ---------------------------------------------------------------------------
if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "VCPKG_ROOT=$VCPKG_ROOT"
    echo "RUNVCPKG_VCPKG_ROOT=$VCPKG_ROOT"
  } >> "$GITHUB_ENV"
fi

log "vcpkg ready at $VCPKG_ROOT"
