#!/usr/bin/env python3
"""Publish a signed NexDesk update manifest.

The client trusts exactly one thing: an Ed25519 signature over the canonical
field list below, checked against a public key baked into the binary. Everything
else (the JSON layout, the CDN, HTTPS) is transport.

Usage
-----
    # 1. once: create a signing key
    python tools/nexdesk_update/publish.py --keygen --key-id 2026-11

    # 2. every release: build the manifest next to the exe
    python tools/nexdesk_update/publish.py \
        --exe dist/NexDesk-1.5.4-x86_64.exe \
        --key 2026-11:%USERPROFILE%/.nexdesk/update-signing.key \
        --notes-fa notes.fa.txt --notes-en notes.en.txt \
        --min-supported 1.5.0 \
        --out site/updates/windows.json

    # 3. before uploading: prove it verifies
    python tools/nexdesk_update/publish.py --verify site/updates/windows.json \
        --pubkey 2026-11:<64 hex>

Dependency: one of `pynacl` or `cryptography` (both are a single wheel install).
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import re
import sys
from pathlib import Path

MANIFEST_PREFIX = "nexdesk-manifest-v1"
SCHEMA = 1
VERSION_RE = re.compile(r"^(\d{1,4})\.(\d{1,4})\.(\d{1,4})$")


# ---------------------------------------------------------------------------
# Crypto (PyNaCl preferred, cryptography accepted)
# ---------------------------------------------------------------------------

def _load_crypto():
    try:
        import nacl.signing  # type: ignore

        return "nacl", nacl.signing
    except Exception:
        pass
    try:
        from cryptography.hazmat.primitives.asymmetric import ed25519  # type: ignore

        return "cryptography", ed25519
    except Exception:
        pass
    sys.exit(
        "error: no Ed25519 library found.\n"
        "       install one of:  pip install pynacl   (or)   pip install cryptography"
    )


def sign_payload(seed: bytes, payload: bytes) -> bytes:
    kind, module = _load_crypto()
    if len(seed) != 32:
        sys.exit("error: the signing key must be exactly 32 bytes")
    if kind == "nacl":
        return bytes(module.SigningKey(seed).sign(payload)[:64])
    private = module.Ed25519PrivateKey.from_private_bytes(seed)
    return private.sign(payload)


def public_key_hex(seed: bytes) -> str:
    kind, module = _load_crypto()
    if kind == "nacl":
        return bytes(module.SigningKey(seed).verify_key).hex()
    private = module.Ed25519PrivateKey.from_private_bytes(seed)
    from cryptography.hazmat.primitives import serialization

    return private.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    ).hex()


def verify_signature(pubkey: bytes, payload: bytes, signature: bytes) -> bool:
    kind, module = _load_crypto()
    if kind == "nacl":
        try:
            module.VerifyKey(pubkey).verify(payload, signature)
            return True
        except Exception:
            return False
    from cryptography.exceptions import InvalidSignature

    try:
        module.Ed25519PublicKey.from_public_bytes(pubkey).verify(signature, payload)
        return True
    except InvalidSignature:
        return False


# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

def canonical_payload(m: dict) -> bytes:
    """Must match `canonical_payload()` in src/nexdesk_update.rs byte for byte."""
    def sha(text: str) -> str:
        return hashlib.sha256(text.encode("utf-8")).hexdigest()

    for name in ("channel", "platform", "version", "url", "sha256", "min_supported", "published_at"):
        value = str(m.get(name, ""))
        if any(ch in value for ch in ("\n", "\r", "\0")):
            sys.exit(f"error: field {name} contains a control character")

    lines = [
        MANIFEST_PREFIX,
        f"schema={int(m['schema'])}",
        f"channel={m['channel']}",
        f"platform={m['platform']}",
        f"version={m['version']}",
        f"url={m['url']}",
        f"sha256={m['sha256']}",
        f"size={int(m['size'])}",
        f"mandatory={'true' if m.get('mandatory') else 'false'}",
        f"min_supported={m.get('min_supported', '')}",
        f"published_at={m['published_at']}",
        f"notes_fa_sha256={sha(m.get('notes_fa', ''))}",
        f"notes_en_sha256={sha(m.get('notes_en', ''))}",
    ]
    return ("\n".join(lines) + "\n").encode("utf-8")


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_key(spec: str) -> tuple[str, bytes]:
    key_id, _, path = spec.partition(":")
    if not key_id or not path:
        sys.exit("error: --key must look like key_id:path/to/seed")
    seed = Path(path).expanduser().read_bytes()
    if len(seed) != 32:
        sys.exit(f"error: {path} is {len(seed)} bytes; expected a raw 32-byte seed")
    return key_id.strip(), seed


def cmd_keygen(args) -> None:
    _load_crypto()
    seed = os.urandom(32)
    out = Path(args.out or Path.home() / ".nexdesk" / "update-signing.key").expanduser()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(seed)
    try:
        os.chmod(out, 0o600)
    except Exception:
        pass
    pub = public_key_hex(seed)
    print(f"private key written to {out}  (keep it off the repo and back it up)")
    print()
    print("Put this in GitHub -> Settings -> Secrets and variables -> Actions -> Variables")
    print(f"  NEXDESK_UPDATE_PUBKEY = {args.key_id}:{pub}")
    print()
    print("Rust literal (if you ever bake it in code):")
    print("  [" + ", ".join(f"0x{b:02x}" for b in bytes.fromhex(pub)) + "]")


def cmd_publish(args) -> None:
    exe = Path(args.exe)
    if not exe.is_file():
        sys.exit(f"error: {exe} does not exist")

    match = re.search(r"-(\d+\.\d+\.\d+)-", exe.name)
    if not match:
        sys.exit("error: cannot read the version from the file name (expected ...-1.5.4-x86_64.exe)")
    version = match.group(1)
    if not VERSION_RE.match(version):
        sys.exit(f"error: version {version} is not x.y.z")

    notes_fa = Path(args.notes_fa).read_text(encoding="utf-8") if args.notes_fa else ""
    notes_en = Path(args.notes_en).read_text(encoding="utf-8") if args.notes_en else ""
    for label, text in (("fa", notes_fa), ("en", notes_en)):
        if len(text) > 4096:
            sys.exit(f"error: notes_{label} is longer than 4096 characters")

    size = exe.stat().st_size
    if not (1024 * 1024 <= size <= 300 * 1024 * 1024):
        sys.exit(f"error: {size} bytes is outside the accepted range")

    published = args.published_at or _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if not re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", published):
        sys.exit("error: --published-at must be YYYY-MM-DDTHH:MM:SSZ")

    manifest = {
        "schema": SCHEMA,
        "channel": args.channel,
        "platform": args.platform,
        "version": version,
        "url": args.url or f"https://nexdesk.ir/updates/{exe.name}",
        "sha256": file_sha256(exe),
        "size": size,
        "mandatory": bool(args.mandatory),
        "min_supported": args.min_supported or "",
        "published_at": published,
        "notes_fa": notes_fa,
        "notes_en": notes_en,
        "signatures": [],
    }

    payload = canonical_payload(manifest)
    for spec in args.key:
        key_id, seed = parse_key(spec)
        manifest["signatures"].append(
            {"key_id": key_id, "sig": sign_payload(seed, payload).hex()}
        )
    if not manifest["signatures"]:
        sys.exit("error: no --key given; a manifest without a signature is rejected by every client")

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(out)

    print(f"wrote {out}")
    print(f"  version   {version}")
    print(f"  size      {size}")
    print(f"  sha256    {manifest['sha256']}")
    print(f"  mandatory {manifest['mandatory']}  min_supported={manifest['min_supported'] or '-'}")
    print(f"  signed by {', '.join(s['key_id'] for s in manifest['signatures'])}")
    print()
    print("Next: upload the exe and this JSON, then verify:")
    print(f"  python {sys.argv[0]} --verify {out} --pubkey <key_id>:<hex>")


def cmd_verify(args) -> None:
    manifest = json.loads(Path(args.verify).read_text(encoding="utf-8"))
    payload = canonical_payload(manifest)
    pub_spec = args.pubkey
    key_id, _, pub_hex = pub_spec.partition(":")
    if not pub_hex:
        key_id, pub_hex = "", pub_spec
    pubkey = bytes.fromhex(pub_hex)
    ok = False
    for entry in manifest.get("signatures", []):
        if key_id and entry.get("key_id") != key_id:
            continue
        if verify_signature(pubkey, payload, bytes.fromhex(entry["sig"])):
            ok = True
            break
    print("signature OK" if ok else "SIGNATURE INVALID")
    sys.exit(0 if ok else 1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Sign and publish a NexDesk update manifest")
    parser.add_argument("--exe", help="the built NexDesk-<version>-<arch>.exe")
    parser.add_argument("--out", help="manifest path (or key path with --keygen)")
    parser.add_argument("--channel", default="stable")
    parser.add_argument("--platform", default="windows-x86_64")
    parser.add_argument("--url", default="", help="download URL; defaults to nexdesk.ir/updates/<file>")
    parser.add_argument("--mandatory", action="store_true")
    parser.add_argument("--min-supported", default="")
    parser.add_argument("--published-at", default="")
    parser.add_argument("--notes-fa", default="")
    parser.add_argument("--notes-en", default="")
    parser.add_argument("--key", action="append", default=[], help="key_id:path (repeat to dual-sign)")
    parser.add_argument("--keygen", action="store_true")
    parser.add_argument("--key-id", default="2026-11")
    parser.add_argument("--verify", default="")
    parser.add_argument("--pubkey", default="")
    args = parser.parse_args()

    if args.keygen:
        cmd_keygen(args)
    elif args.verify:
        if not args.pubkey:
            sys.exit("error: --verify needs --pubkey key_id:hex")
        cmd_verify(args)
    else:
        if not args.exe:
            parser.error("--exe is required unless --keygen or --verify is used")
        cmd_publish(args)


if __name__ == "__main__":
    main()
