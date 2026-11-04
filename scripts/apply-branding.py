#!/usr/bin/env python3
"""
NexDesk branding pass.

Rewrites upstream RustDesk 1.5.0 into the NexDesk product identity. Every
edit is asserted, so re-running against an already-branded tree reports
"already applied" instead of silently corrupting files.

Usage:  python scripts/apply-branding.py [--check]
        --check  report what would change, write nothing
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

BRAND = "NexDesk"
BRAND_FA = "نکس دسک"
VERSION_SUFFIX = "1.5.0"

# --------------------------------------------------------------- file edits --
# (relative path, old, new, expected occurrences)
EDITS: list[tuple[str, str, str, int]] = [
    # ---- Rust core identity ------------------------------------------------
    (
        "libs/hbb_common/src/config.rs",
        'RwLock::new("RustDesk".to_owned())',
        f'RwLock::new("{BRAND}".to_owned())',
        1,
    ),
    (
        "src/auth_2fa.rs",
        'const ISSUER: &str = "RustDesk";',
        f'const ISSUER: &str = "{BRAND}";',
        1,
    ),
    # ---- Flutter window / branding -----------------------------------------
    (
        "flutter/windows/CMakeLists.txt",
        'set(BINARY_NAME "rustdesk")',
        f'set(BINARY_NAME "{BRAND}")',
        1,
    ),
    (
        "flutter/lib/desktop/widgets/tabbar_widget.dart",
        '''                            child: const Text(
                              "RustDesk",
                              style: TextStyle(fontSize: 13),
                            ).marginOnly(left: 2))''',
        f'''                            child: const Text(
                              "{BRAND}",
                              style: TextStyle(fontSize: 13),
                            ).marginOnly(left: 2))''',
        1,
    ),
    # ---- Windows version resource ------------------------------------------
    (
        "flutter/windows/runner/Runner.rc",
        'VALUE "CompanyName", "Purslane Tech Pte. Ltd." "\\0"',
        f'VALUE "CompanyName", "{BRAND}" "\\0"',
        1,
    ),
    (
        "flutter/windows/runner/Runner.rc",
        'VALUE "FileDescription", "RustDesk Remote Desktop" "\\0"',
        f'VALUE "FileDescription", "{BRAND} Remote Desktop" "\\0"',
        1,
    ),
    (
        "flutter/windows/runner/Runner.rc",
        'VALUE "InternalName", "rustdesk" "\\0"',
        f'VALUE "InternalName", "{BRAND}" "\\0"',
        1,
    ),
    (
        "flutter/windows/runner/Runner.rc",
        'VALUE "OriginalFilename", "rustdesk.exe" "\\0"',
        f'VALUE "OriginalFilename", "{BRAND}.exe" "\\0"',
        1,
    ),
    (
        "flutter/windows/runner/Runner.rc",
        'VALUE "ProductName", "RustDesk" "\\0"',
        f'VALUE "ProductName", "{BRAND}" "\\0"',
        1,
    ),
    (
        "flutter/windows/runner/Runner.rc",
        'VALUE "LegalCopyright", "Copyright © 2026 Purslane Tech Pte. Ltd. All rights reserved." "\\0"',
        f'VALUE "LegalCopyright", "Copyright © 2026 {BRAND}. Based on RustDesk (AGPL-3.0)." "\\0"',
        1,
    ),
    # ---- packaging: emit NexDesk.exe, not rustdesk.exe ---------------------
    (
        "build.py",
        "-e ../../{flutter_build_dir_2}/rustdesk.exe'",
        "-e ../../{flutter_build_dir_2}/" + BRAND + ".exe'",
        1,
    ),
    (
        "build.py",
        "f'./rustdesk-{version}-install.exe'",
        "f'./" + BRAND + "-{version}.exe'",
        1,
    ),
    (
        "build.py",
        "f'output location: {os.path.abspath(os.curdir)}/rustdesk-{version}-install.exe'",
        "f'output location: {os.path.abspath(os.curdir)}/" + BRAND + "-{version}.exe'",
        1,
    ),
]

# --------------------------------------------------------------- theme ------
# RustDesk ships a blue accent on near-black chrome; NexDesk is a green identity
# on deep green surfaces. See brand/palette.json for the source of truth.
THEME_EDITS: list[tuple[str, str, str]] = [
    # ordered: the dialog border must be recoloured before the generic
    # card-surface pass below sweeps every remaining 24252B.
    ("color: Color(0xFF24252B),", "color: Color(0xFF1C4529),"),
    ("0xFF24252B", "0xFF0E2317"),

    ("static const Color accent = Color(0xFF0071FF);",
     "static const Color accent = Color(0xFF22C55E);"),
    ("static const Color accent50 = Color(0x770071FF);",
     "static const Color accent50 = Color(0x7722C55E);"),
    ("static const Color accent80 = Color(0xAA0071FF);",
     "static const Color accent80 = Color(0xAA22C55E);"),
    ("static const Color button = Color(0xFF2C8CFF);",
     "static const Color button = Color(0xFF16A34A);"),
    ("static const Color idColor = Color(0xFF00B6F0);",
     "static const Color idColor = Color(0xFF4ADE80);"),
    ("static const Color canvasColor = Color(0xFF212121);",
     "static const Color canvasColor = Color(0xFF08120C);"),
    ("static const Color grayBg = Color(0xFFEFEFF2);",
     "static const Color grayBg = Color(0xFFF1F8F3);"),
    ("scaffoldBackgroundColor: Color(0xFF18191E),",
     "scaffoldBackgroundColor: Color(0xFF07130D),"),
    ("dialogBackgroundColor: Color(0xFF18191E),",
     "dialogBackgroundColor: Color(0xFF07130D),"),
    ("hoverColor: Color.fromARGB(255, 45, 46, 53),",
     "hoverColor: Color.fromARGB(255, 22, 52, 34),"),
    ("primary: Colors.blue,", "primary: Color(0xFF22C55E),"),
]

# ------------------------------------------------------------- asset copies --
ASSETS: list[tuple[str, str]] = [
    ("brand/nexdesk-icon.ico", "res/icon.ico"),
    ("brand/nexdesk-icon-512.png", "res/icon.png"),
    ("brand/nexdesk-32x32.png", "res/32x32.png"),
    ("brand/nexdesk-64x64.png", "res/64x64.png"),
    ("brand/nexdesk-128x128.png", "res/128x128.png"),
    ("brand/nexdesk-128x128@2x.png", "res/128x128@2x.png"),
    ("brand/nexdesk-tray.ico", "res/tray-icon.ico"),
    ("brand/nexdesk-tray-dark-x2.png", "res/mac-tray-dark-x2.png"),
    ("brand/nexdesk-icon-512.png", "res/mac-icon.png"),
    ("brand/nexdesk-icon.ico", "flutter/windows/runner/resources/app_icon.ico"),
    ("brand/nexdesk-tray-light-x2.png", "res/mac-tray-light-x2.png"),
    ("brand/nexdesk-256x256.png", "flutter/assets/icon.png"),
]


def apply_edits(check: bool) -> tuple[int, int, list[str]]:
    changed = skipped = 0
    problems: list[str] = []
    for rel, old, new, count in EDITS:
        path = ROOT / rel
        if not path.exists():
            problems.append(f"missing file: {rel}")
            continue
        text = path.read_text(encoding="utf-8")
        if new in text and old not in text:
            skipped += 1
            continue
        found = text.count(old)
        if found != count:
            problems.append(f"{rel}: expected {count} match(es) of {old[:50]!r}, found {found}")
            continue
        if not check:
            path.write_text(text.replace(old, new), encoding="utf-8")
        changed += 1
    return changed, skipped, problems


def apply_theme(check: bool) -> int:
    path = ROOT / "flutter/lib/common.dart"
    text = path.read_text(encoding="utf-8")
    original = text
    for old, new in THEME_EDITS:
        text = text.replace(old, new)
    if text != original and not check:
        path.write_text(text, encoding="utf-8")
    return 0 if text == original else 1


def copy_assets(check: bool) -> int:
    # Assets are authored outside the source tree. When they are absent (CI,
    # or a fresh clone) the icons already committed under res/ are authoritative.
    brand_dir = ROOT.parent / "brand"
    if not brand_dir.is_dir():
        return 0
    n = 0
    for src_rel, dst_rel in ASSETS:
        src = brand_dir / Path(src_rel).name
        if not src.exists():
            print(f"  ! missing brand asset {src}")
            continue
        if not check:
            shutil.copy2(src, ROOT / dst_rel)
        n += 1
    return n


def main() -> int:
    global ROOT
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="report what would change, write nothing")
    ap.add_argument("--root", type=Path, default=None,
                    help="source tree to brand (default: the repo this script lives in)")
    args = ap.parse_args()
    if args.root is not None:
        ROOT = args.root.resolve()
        if not (ROOT / "Cargo.toml").exists():
            print(f"not a RustDesk source tree: {ROOT}")
            return 2

    print(f"branding {ROOT} as {BRAND} ({BRAND_FA})")
    changed, skipped, problems = apply_edits(args.check)
    theme_changed = apply_theme(args.check)
    assets = copy_assets(args.check)

    print(f"  text edits applied : {changed}")
    print(f"  already branded    : {skipped}")
    print(f"  theme file updated : {'yes' if theme_changed else 'no'}")
    print(f"  assets copied      : {assets}")

    if problems:
        print("\nPROBLEMS:")
        for p in problems:
            print("  -", p)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
