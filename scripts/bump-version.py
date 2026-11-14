#!/usr/bin/env python3
"""
Set the NexDesk version everywhere the build reads it.

`build.py` takes the version from Cargo.toml, and the compiled-in `crate::VERSION`
(used by the updater's "is this newer?" comparison) comes from the same place.
Flutter's pubspec carries a separate copy that ends up in the bundle metadata,
so both are written together to stop them drifting apart.

Two workspace members carry the version for a different reason: their
VERSIONINFO is stamped by winres straight from `[package] version`, and both
ship inside the payload. `libs/portable` produces the single-file exe a user
actually downloads, and `libs/virtual_display/dylib` produces a DLL the app
loads at runtime. When those lagged behind the app (1.5.8 and 0.1.0 against
1.5.11) the payload reported three different versions of itself, which is a
heuristic signal for scanners and a metadata failure for code-signing review.
They are bumped here, together with their `Cargo.lock` entries, because
`cargo build --locked` refuses to run when the lock disagrees with the manifest.

Usage:  python scripts/bump-version.py 1.5.1 [--root .]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

CARGO = "Cargo.toml"
PUBSPEC = "flutter/pubspec.yaml"
LOCK = "Cargo.lock"

# Workspace members whose `[package] version` is the product version, because
# winres stamps their VERSIONINFO from it. See their Cargo.toml comments.
# `virtual_display` is a plain rlib with no VERSIONINFO, but it is listed so a
# version bump cannot leave it stranded at an old number in Cargo.lock.
VERSIONED_MEMBERS = (
    "libs/portable/Cargo.toml",
    "libs/virtual_display/dylib/Cargo.toml",
    "libs/virtual_display/Cargo.toml",
)

# The `[[package]]` names those members appear under in Cargo.lock.
LOCKED_MEMBERS = (
    "rustdesk-portable-packer",
    "dylib_virtual_display",
    "virtual_display",
)


def _bump_package_version(path: Path, version: str) -> bool:
    """Rewrite the first `version = "..."` line, i.e. the [package] one."""
    text = path.read_text(encoding="utf-8")
    updated, count = re.subn(
        r'(?m)^version = "[^"]*"', f'version = "{version}"', text, count=1
    )
    if count == 0:
        raise SystemExit(f'no [package] version line found in {path}')
    if updated == text:
        return False
    path.write_text(updated, encoding="utf-8")
    return True


def _bump_lock_entry(text: str, name: str, version: str) -> tuple[str, bool]:
    """Rewrite the version of one `[[package]]` block, matched by name."""
    pattern = rf'(?m)^(name = "{re.escape(name)}"\nversion = ")[^"]*(")'
    updated, count = re.subn(pattern, rf"\g<1>{version}\g<2>", text, count=1)
    if count == 0:
        raise SystemExit(f'no [[package]] name = "{name}" entry in {LOCK}')
    return updated, updated != text


def bump(root: Path, version: str) -> list[str]:
    changed: list[str] = []

    cargo = root / CARGO
    if not cargo.exists():
        raise SystemExit(f"missing {cargo}")
    if _bump_package_version(cargo, version):
        changed.append(CARGO)

    pubspec = root / PUBSPEC
    if pubspec.exists():
        text = pubspec.read_text(encoding="utf-8")
        # Preserve the existing Flutter build number; only the semver moves.
        match = re.search(r"(?m)^version:\s*[0-9.]+\+(\d+)\s*$", text)
        build = match.group(1) if match else "1"
        updated = re.sub(
            r"(?m)^version:.*$", f"version: {version}+{build}", text, count=1
        )
        if updated != text:
            pubspec.write_text(updated, encoding="utf-8")
            changed.append(PUBSPEC)

    for member in VERSIONED_MEMBERS:
        path = root / member
        if not path.exists():
            raise SystemExit(f"missing {path}")
        if _bump_package_version(path, version):
            changed.append(member)

    lock = root / LOCK
    if lock.exists():
        text = lock.read_text(encoding="utf-8")
        dirty = False
        for name in LOCKED_MEMBERS:
            text, entry_changed = _bump_lock_entry(text, name, version)
            dirty = dirty or entry_changed
        if dirty:
            lock.write_text(text, encoding="utf-8")
            changed.append(LOCK)

    return changed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("version", help="new version, with or without a leading v")
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = ap.parse_args()

    version = args.version.strip().lstrip("vV")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        print(f"refusing to use a non-semver version: {args.version!r}")
        return 2

    changed = bump(args.root.resolve(), version)
    if changed:
        print(f"version -> {version} ({', '.join(changed)})")
    else:
        print(f"already at {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
