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
# 2. The tool binary, built from source when it is missing.
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
# 3. Hand the paths to the following steps.
# ---------------------------------------------------------------------------
if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "VCPKG_ROOT=$VCPKG_ROOT"
    echo "RUNVCPKG_VCPKG_ROOT=$VCPKG_ROOT"
  } >> "$GITHUB_ENV"
fi

log "vcpkg ready at $VCPKG_ROOT"
