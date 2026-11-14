# NexDesk

**نکس دسک** — a free remote desktop client for Windows and Android, with a
Persian-first interface and a self-hosted rendezvous server.

NexDesk is a fork of [RustDesk](https://github.com/rustdesk/rustdesk), rebuilt
and rebranded by [Yar Holding](https://nexdesk.ir). It is free of charge and
funded by advertising shown on the home screen.

- **Download:** <https://nexdesk.ir>
- **Source:** this repository (AGPL-3.0 — see [Licence](#licence))
- **Server:** self-hosted `hbbs` / `hbbr`, not RustDesk's public infrastructure

> [!Caution]
> **Misuse disclaimer.** NexDesk is a remote-support tool. Using it to access a
> device you do not own or have not been authorised to access is illegal in most
> jurisdictions and is contrary to this project's guidelines. Sessions started
> through NexDesk display a visible connection indicator on the controlled
> machine, and unattended access requires the device owner to set a permanent
> password. The maintainers do not condone and are not responsible for misuse.
> See [SECURITY.md](SECURITY.md) for the abuse-reporting process.

## What it does

- Remote desktop control of Windows and Android devices, with hardware codec
  and VRAM capture enabled for low-latency sessions.
- File transfer, TCP tunnelling, and a portable mode that runs without
  installation.
- Privacy mode, which blanks the controlled screen while a session is active.
- Persian (RTL) interface by default.
- Built-in updater that polls `https://nexdesk.ir/api/update.php` and verifies
  the downloaded installer's SHA-256 before running it.

NexDesk talks to its own rendezvous server. The hostname and public key are
baked into the binary at build time from the `NEXDESK_SERVER` and
`NEXDESK_SERVER_KEY` repository variables, so a stock build of this repository
does **not** contact RustDesk's public servers.

## Free, and ad-supported

NexDesk costs nothing. Development is funded by a single advertising slot on the
home screen and a dismissible banner in the mobile app.

The ad request is anonymous: it is a plain `GET https://ad.yar.one/` carrying one
cache-busting timestamp and nothing else — no device identifier, no install
identifier, no user identifier, no session token, and no cookie jar. The ad
markup is parsed and rendered natively; no web view is embedded and no
JavaScript is executed. See [PRIVACY.md](PRIVACY.md) for the full disclosure,
and `flutter/test/ad_request_anonymity_test.dart` for the test that keeps it
that way.

## Building from source

The supported build path is the GitHub Actions workflow
[`.github/workflows/nexdesk-windows.yml`](.github/workflows/nexdesk-windows.yml),
which produces both the MSI installer and the single-file portable executable.
It pins the toolchain versions RustDesk's patched Flutter engine requires
(Rust 1.75, Flutter 3.24.5, LLVM 15.0.6) and installs the `vcpkg` dependencies
(`ffmpeg`, `libvpx`, `opus`, `libyuv`, `aom`) before compiling.

To build on a Windows machine instead, run:

```bat
BUILD-NexDesk.cmd
```

which drives `build/build-all.ps1` → `build/build-windows.ps1`. That script
detects a missing toolchain and can install it, so a cold first run downloads
roughly 8 GB and takes 40–60 minutes. Output lands in `dist/`.

The version is read from `Cargo.toml`; `python scripts/bump-version.py <x.y.z>`
updates every place it is duplicated — `Cargo.toml`, `flutter/pubspec.yaml`, the
portable packer and the virtual-display DLL manifests, and their `Cargo.lock`
entries. Bump it with that script rather than by hand, because
`cargo build --locked` fails when the lock and the manifests disagree.

### Repository layout

| Path | Contents |
|---|---|
| `src/` | Rust core: session handling, capture, input, the updater |
| `flutter/` | Flutter UI shell (Windows and Android) |
| `libs/portable/` | Single-file self-extracting packer |
| `libs/virtual_display/` | Virtual display driver and its DLL |
| `res/msi/` | WiX v4 project for the MSI installer |
| `scripts/` | Version bumping and branding helpers |
| `docs/` | Contributor and policy documentation |

## Code signing

Release binaries are Authenticode-signed, with a timestamp, by the SignPath
Foundation. The signing policy, the exact build → sign → pack ordering, and the
commands to verify a download are in [docs/CODE-SIGNING.md](docs/CODE-SIGNING.md).

To check a file you downloaded:

```powershell
Get-AuthenticodeSignature .\NexDesk-<version>-x64.msi |
  Format-List Status, SignerCertificate, TimeStamperCertificate
```

`Status` must read `Valid`. The publisher shown is **SignPath Foundation** — the
certificate is issued to the foundation rather than to NexDesk, which is the
normal arrangement for free open-source code signing.

## Security and privacy

- [SECURITY.md](SECURITY.md) — threat model, how to report a vulnerability, and
  the abuse-reporting process.
- [PRIVACY.md](PRIVACY.md) — every network request the client makes, and what it
  carries.

## Contributing

Issues and pull requests are welcome. Because this is a fork, `main` carries the
NexDesk changes on top of an `upstream` branch that tracks
`rustdesk/rustdesk`; the sync workflow merges new upstream releases and bumps the
version. Please open an issue before starting work on anything larger than a bug
fix, so the change does not collide with an upstream merge.

## Licence

NexDesk is distributed under the **GNU Affero General Public License v3.0**. See
[LICENCE](LICENCE) for the full text.

This program is free software: you can redistribute it and/or modify it under
the terms of the AGPL as published by the Free Software Foundation, either
version 3 of the Licence, or (at your option) any later version.

Because NexDesk is a modified version of RustDesk, the AGPL requires that the
complete corresponding source of the version you are running remains available.
If you operate a modified NexDesk as a network service, section 13 of the
Licence requires you to offer its source to the users of that service.

RustDesk is © RustDesk and contributors, licensed under the AGPL-3.0. NexDesk's
changes are © 2026 NexDesk / Yar Holding, released under the same licence.
