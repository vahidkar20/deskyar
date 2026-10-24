#!/usr/bin/env python3
"""
Set the DeskYar version everywhere the build reads it.

`build.py` takes the version from Cargo.toml, and the compiled-in `crate::VERSION`
(used by the updater's "is this newer?" comparison) comes from the same place.
Flutter's pubspec carries a separate copy that ends up in the bundle metadata,
so both are written together to stop them drifting apart.

Usage:  python scripts/bump-version.py 1.5.1 [--root .]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

CARGO = "Cargo.toml"
PUBSPEC = "flutter/pubspec.yaml"


def bump(root: Path, version: str) -> list[str]:
    changed: list[str] = []

    cargo = root / CARGO
    if not cargo.exists():
        raise SystemExit(f"missing {cargo}")
    text = cargo.read_text(encoding="utf-8")
    updated, count = re.subn(
        r'(?m)^version = "[^"]*"', f'version = "{version}"', text, count=1
    )
    if count == 0:
        raise SystemExit(f'no [package] version line found in {cargo}')
    if updated != text:
        cargo.write_text(updated, encoding="utf-8")
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
