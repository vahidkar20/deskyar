# SignPath application package

Everything in this file is ready to paste. It covers the two things only the
project owner can do: submitting the application at
<https://signpath.org/apply>, and publishing the policy pages on `nexdesk.ir`.

Before submitting, confirm the repository work in the plan is merged and that
`docs/CODE-SIGNING.md` has a real name in the Reviewer row.

---

## 1. Application form answers

SignPath's form is short and free-text. Ambiguity is what gets an application
bounced, so each answer below is complete on its own.

### Project name and description

> NexDesk — a free remote desktop client for Windows and Android with a
> Persian-first interface, maintained by Yar.One Holding (Iran). Distributed from
> https://nexdesk.ir.

### Repository

> https://github.com/vahidkar20/deskyar
>
> NexDesk is a fork of rustdesk/rustdesk. The fork relationship is visible on
> GitHub. `main` descends from upstream release tags and the `upstream` branch
> tracks them verbatim; the sync workflow merges new upstream releases.

### Licence

> GNU Affero General Public License v3.0 or later (OSI-approved). The full text is
> in `LICENCE` at the repository root. There is no dual licensing, no commercial
> edition, and no proprietary component in the signed artifacts.
>
> The one third-party binary in the payload is `flutter_windows.dll` — the Flutter
> engine, patched by the RustDesk project and licensed BSD 3-Clause. It is fetched
> at build time from rustdesk/engine and is **not** signed by us, because we did
> not build it. It is declared in `docs/CODE-SIGNING.md` and in the installer
> licence text.
>
> A kernel-mode virtual display driver (usbmmidd_v2) used to be redistributed
> inside the package. It has been removed: its author publishes no licence, so
> redistributing it made the package proprietary-in-part. The feature now
> requires the driver to be installed separately.

### Build process

> GitHub Actions, workflow `.github/workflows/nexdesk-windows.yml`, on
> `windows-2022`, from source in this repository. Toolchain is pinned to Rust
> 1.75, Flutter 3.24.5 and LLVM 15.0.6, with native dependencies from vcpkg
> (ffmpeg, libvpx, opus, libyuv, aom). No binary artifact is committed to the
> repository.

### What is signed, and why in two stages

> Two artifact configurations, because the portable build is a self-extracting
> container that SignPath cannot traverse.
>
> `nexdesk-inner` — `NexDesk.exe`, `librustdesk.dll`, `dylib_virtual_display.dll`.
> These are signed **before** the packer compresses them into `data.bin`, because
> Windows evaluates exactly those binaries after extraction; a signature on the
> outer stub alone would not cover them.
>
> `nexdesk-outer` — the single-file portable executable and the MSI.
>
> Both stages use Authenticode with SHA-256 and RFC 3161 timestamping. This means
> two manual approvals per release, which is a consequence of the container
> format rather than a choice.

### Fork relationship

> Upstream rustdesk/rustdesk publishes signed Windows builds. NexDesk's `main`
> is a descendant of upstream release tags and the repository is a GitHub fork of
> rustdesk/rustdesk. NexDesk changes branding, the update channel and the
> installer; it does not modify the remote-session protocol.

### Abuse policy

> Documented in `SECURITY.md`. A session cannot start against a device whose
> owner has not granted access; the controlled side shows a visible connection
> indicator for the session's duration; unattended access requires the device
> owner to set a permanent password. Confirmed abuse reports result in the device
> ID being blocked from the rendezvous service. The reporting address is on the
> website.

### Third-party content

> The application fetches nothing from a third party and displays no third-party
> content. Every network destination it contacts is either operated by NexDesk —
> `rd.nexdesk.ir` for the rendezvous server, `nexdesk.ir` for the account API and
> the update feed — or supplied by the user. No remote markup or remote script is
> parsed, and no web view is embedded.
>
> An earlier build carried an advertising slot served from the project's own ad
> server. It has been removed, and a build gate now fails if it returns.
>
> The application installs nothing outside its own directory, injects nothing
> into other processes, changes no browser settings, and shows no pop-ups outside
> its own window.

### Why the project needs signing

> Windows shows "Unknown publisher" in UAC and SmartScreen for every release,
> which suppresses installation among the Iranian business users the product
> targets. The project has no revenue for a commercial certificate.

### MFA and approval

> Every person in the roles table has MFA enabled on GitHub and on SignPath. Each
> signing request is approved manually by the Approver; no build is signed
> automatically.

---

## 2. `/code-signing` — the policy page

Must exist on the site, linked from the homepage and from `/download`. Publish
the English text below (reviewers read English) and a Persian translation
underneath it.

```
Free code signing provided by SignPath.io, certificate by SignPath Foundation

NexDesk's Windows releases are Authenticode-signed with an RFC 3161 timestamp
before publication. The certificate is issued to the SignPath Foundation, so that
is the publisher name Windows shows — certificate authorities do not issue
code-signing certificates to open-source projects in the project's own name.

What is signed
  NexDesk-<version>-x64.msi            signed
  NexDesk-<version>-x86_64.exe         signed
  NexDesk.exe (inside the payload)     signed
  librustdesk.dll (inside the payload) signed
  dylib_virtual_display.dll            signed
  flutter_windows.dll                  not signed — RustDesk's patched Flutter
                                       engine, BSD, not built by this project
  Windows Installer custom actions     not signed separately — compiled into the
                                       MSI, which is signed

Roles
  Author    @vahidkar20        may modify source without additional review
  Reviewer  <NAME>             reviews every change from a non-committer
  Approver  @vahidkar20        approves each signing request

Multi-factor authentication is required on both GitHub and SignPath for every
person listed above. Every signing request is approved by a human before the
certificate is used; no build is signed automatically.

Privacy: see /privacy. No personal data is transferred to SignPath.io or the
SignPath Foundation. Signing requests contain only compiled binaries.

Verifying a download
  Get-AuthenticodeSignature .\NexDesk-<version>-x64.msi |
    Format-List Status, SignerCertificate, TimeStamperCertificate

  Status must read Valid, and SignerCertificate.Subject must contain
  "SignPath Foundation". A non-null TimeStamperCertificate means the signature
  stays valid after the certificate expires.

Last updated: <date>
```

---

## 3. `/privacy`

Render `PRIVACY.md` from the repository. It already lists every network
destination the application contacts, and what is stored locally. Link it from
the footer of **every** page, not only from the policy page.

---

## 4. `/licence`

```
NexDesk is free software, licensed under the GNU Affero General Public License,
version 3 or (at your option) any later version.

Copyright (C) 2026 Yar.One Holding.
Based on RustDesk, Copyright (C) RustDesk and contributors, also AGPL-3.0.

Source code: https://github.com/vahidkar20/deskyar

Under section 13 of the licence, if you run a modified version of this program as
a network service, you must offer the users of that service the corresponding
source.

Third-party components: flutter_windows.dll (Flutter engine patched by RustDesk,
BSD 3-Clause), libvpx, libyuv, opus, aom and ffmpeg via vcpkg under their
respective licences.
```

---

## 5. Edits to the existing pages

**Homepage footer** — add links to `/code-signing`, `/privacy`, `/licence`.

**Homepage body** — one sentence, near the download call to action:

> Windows builds are code-signed; the publisher shown is SignPath Foundation.

**`/download`** — the same literal attribution line, a link to `/code-signing`,
and one paragraph explaining why the publisher is a foundation rather than
NexDesk. Without that sentence users read "SignPath Foundation" as a third party.

**`/download` FAQ — delete this answer.** It currently tells every visitor the
file has no commercial signature, and it is the first thing a reviewer will read:

> «نبود امضای تجاری» — the FAQ entry explaining that the SmartScreen warning
> appears because the file is new and has no commercial signature.

Replace it with an answer that is true once signing is live: the file is signed,
the publisher is SignPath Foundation, and SmartScreen may still warn for a new
release until enough installations accumulate.

---

## 6. Remaining owner checklist

| # | Task | Blocks |
|---|---|---|
| 1 | Fill the Reviewer name in `docs/CODE-SIGNING.md` and on `/code-signing` | submission |
| 2 | Publish `/code-signing`, `/privacy`, `/licence`; link from footer | submission |
| 3 | Delete the "no commercial signature" FAQ answer | submission |
| 4 | Enable MFA on GitHub and on the SignPath account | submission |
| 5 | Submit the application at signpath.org/apply | everything |
| 6 | After acceptance: create the project, the two artifact configurations and the policy, then set `SIGNPATH_ORG_ID`, `SIGN_ENABLED=true` and the `SIGNPATH_API_TOKEN` secret | first signed release |
| 7 | After acceptance: approve each signing request | each release |
