# Security policy

## Reporting a vulnerability

Email **info@nexdesk.ir** with a description, the version affected, and steps to
reproduce. Please do not open a public issue for a vulnerability.

We aim to acknowledge within 5 working days. There is no bug bounty programme.

## Supported versions

Only the latest release receives fixes. NexDesk follows upstream RustDesk
releases on a best-effort basis through
`.github/workflows/nexdesk-sync-upstream.yml`.

## What is in scope

- The Rust core in `src/` and the libraries in `libs/`
- The Flutter UI in `flutter/`
- The Windows installer in `res/msi/`
- The release workflows in `.github/workflows/`

## Known limitations

These are known and tracked, not vulnerabilities to report:

- **Releases are not code signed.** There is no Authenticode certificate behind
  the binaries, so Windows shows *Unknown publisher* and SmartScreen may warn.
- **Update manifests are not signature-checked.** `verify_signatures()` exists in
  `src/nexdesk_update.rs` but has no caller, and manifests built from the update
  API carry an empty signature list. Update integrity currently rests on HTTPS,
  a host allowlist, and the SHA-256 the API returns. See
  [docs/UPDATE.md](docs/UPDATE.md).
- **The updater installs a downloaded executable.** A host allowlist restricts
  where it can come from, but the file is executed rather than verified against a
  publisher signature.

## Scope of upstream issues

NexDesk is a fork of [RustDesk](https://github.com/rustdesk/rustdesk). If the
issue also affects upstream, report it there as well — it is more likely to be
fixed once, upstream, than twice.
