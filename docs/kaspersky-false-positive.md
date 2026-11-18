# Kaspersky false positive — NexDesk (Android)

> **1.5.12 note:** the final stable build restores the ad channel at the owner's
> request. The vc92/vc93 measurements and the OpenTip report below describe the
> ad-free test builds; the 1.5.12 scan is a separate file and must be treated
> separately. Do not attribute the vc93 zero-network result to 1.5.12.

Cafe Bazaar rejected the upload with:

> version code: 79, cpu architecture: arm64-v8a, armeabi-v7a
> بسته بارگذاری شده توسط «سپر امنیت بازار» بررسی شده است و توسط آنتی‌ویروس(های)
> «Kaspersky» به عنوان بدافزار «HEUR:Trojan.AndroidOS.Fakeapp.fm» شناخته شده است.

`HEUR:` means a heuristic verdict, not a signature match. The family name states
the claim being made: an application that presents itself as another application.
This one does not. It has its own package name, its own signing certificate, its
own brand, its own server, and since version code 85 its own name on every system
surface it creates.

A second verdict appeared when the owner scanned the APK directly, and it changes
the argument in our favour:

```
Malware           HEUR:Trojan.AndroidOS.Fakeapp.fm
Adware and other  not-a-virus:HEUR:RemoteAdmin.AndroidOS.RustDesk.a
```

A third scan, of the version-93 build (SHA-256
`699CF3C3F1C5DFBE5D1E964512770F1EED13370109CB17D2C88EE83169237088`), returned the
same two detections. The OpenTip report for that file was produced on 2026-11-18
13:06 with databases updated the same day at 01:42. It lists **two** detections —
one Malware and one Adware/other — and **zero** suspicious activities, **zero**
network activities, and **zero** extracted files. The public report does not print
the detection names; the Bazaar scanner's report is what names `Fakeapp` and
`RemoteAdmin`.

`not-a-virus:` is Kaspersky's own prefix for *not malware*: it is the riskware
category for remote-administration tools, and this one is named after RustDesk
because the engine has recognised the RustDesk core inside the APK. So the same
scan says both "this is a RustDesk-based remote-admin tool" and "this is a fake
app". Both cannot be true of the same binary. The consistent reading is the first
one: a GPL fork of a known remote-desktop project, which is exactly what it is.
The `Fakeapp` hit is the heuristic misfiring on a repackaged remote-access client
- the shape, not the behaviour.

## Ten builds, one unchanged verdict

| versionCode | what changed | Kaspersky result |
|---|---|---|
| 82 | boot receiver `exported=false`, `allowBackup=false`, debug action removed | unchanged |
| 83 | overlay-permission prompt removed from the normal flow | unchanged |
| 84 | native library renamed `librustdesk.so` → `libnexdesk.so`, scheme `nexdesk://` | unchanged |
| 85 | notification title, channel id/name and virtual-display name renamed | unchanged |
| 88–91 | every upstream string purged from the binaries: account API, version feed, Ed25519 key, `RustDesk` in 583 places across 54 translation files, the Dart snapshot, the custom-client loader | unchanged |
| 92 | the live advertising channel removed | unchanged |
| 93 | the Dart package renamed `flutter_hbb` → `nexdesk`; share links changed to `nexdesk://` | unchanged (OpenTip, 2026-11-18) |

Every independent content change since 82 returned the same two detections.

An earlier draft of this document carried a fifth row here, claiming version 86
removed the advertising slot. That was false. The slot was still in `libapp.so` at
version codes 85, 90 and 91 — verified by byte search on the published APKs — and it
was removed for the first time in version 92. Versions 92 and 93 are the data points
that test it; both returned the same two detections.

## What actually differs from upstream RustDesk 1.5.3

Compared archive to archive against `rustdesk-1.5.3-universal-signed.apk`
(SHA-256 `2223ab4a1be46f841e50bbd15d6b81b1618658530c6d382f52acfa61febf566b`,
signer `O=carriez, CN=zhou huabing`):

| | NexDesk 1.5.11+85 | RustDesk 1.5.3 |
|---|---|---|
| package | `ir.nexdesk.app` | `com.carriez.flutter_hbb` |
| Rust core | `libnexdesk.so` 36.72 MB | `librustdesk.so` 37.80 MB |
| Dart AOT | `libapp.so` 12.39 MB | `libapp.so` 12.52 MB |
| sdk | 22 → 36 | 22 → 36 |

Entries present in NexDesk and absent upstream: four Vazirmatn font files, one
`icon.png`, and the signature block. Nothing else. The Rust core is 1.08 MB
*smaller* than upstream's and the Dart snapshot is 130 KB *smaller* — this build
adds no capability to the RustDesk core, it removes some.

## Two controls, one conclusion

**Control 1 — upstream.** `rustdesk-1.5.3-universal-signed.apk`, scanned with the
same tool:

```
Adware and other  not-a-virus:HEUR:RemoteAdmin.AndroidOS.RustDesk.a
```

No `Fakeapp`. So `RemoteAdmin.RustDesk.a` is inherent to the RustDesk core and
appears on the official build too. It is correct, it is the riskware category, and
it is not what Bazaar objected to.

**Control 2 — this fork with its only added capability removed.** The fork's one
addition to upstream was a live advertising slot: the home pane fetched a third-party
page and parsed its markup into native widgets. It was present in every build up to
and including version 91 — an earlier draft of this document claimed version 86
removed it, and that claim was false. Version 92 removed it; the scan returned the
same two detections. Version 93 then renamed the Dart package from upstream's
`flutter_hbb` to `nexdesk` and changed the generated share link to `nexdesk://`; the
OpenTip scan of that build also returned the same two detections, with zero
suspicious activities, zero network activities and zero extracted files. There is no
remaining behavioural difference to remove.

## What that leaves

After those two controls, the complete difference between this build and the
official one that is *not* flagged is:

| difference | removable? |
|---|---|
| package name `ir.nexdesk.app` instead of `com.carriez.flutter_hbb` | no — a fork must not ship upstream's package name |
| signing certificate `CN=NexDesk` instead of `CN=zhou huabing` | no — we do not hold upstream's key, and should not |
| four Persian font files and one icon | yes, but they are not executable and carry no behaviour |
| the Rust core is 1.08 MB *smaller* than upstream's | no — that is less code, not more |

**Measured:** every content-level difference from upstream has been removed and
verified, and the verdict did not move across version 92 or version 93. The OpenTip
report for version 93 shows zero suspicious activities, zero network activities and
zero extracted files.

**Inferred:** `Fakeapp` is not reachable from the content of the package. The
remaining signal is the identity of the RustDesk engine — the same machine code
under a different certificate. That is consistent with a claim about identity, not
behaviour, and no build can change who signs it without replacing the engine. This
is why the next step is a reanalysis request, not another code change.

## What to say about the riskware line

Do not ask Kaspersky to remove `RemoteAdmin.RustDesk.a`. Their own scan returns
it for upstream RustDesk as well, so it is the correct classification for a
remote-administration tool, and Bazaar did not object to it. The request is only
about `Fakeapp`.

## How to send it

Upload the version-93 APK at <https://opentip.kaspersky.com>, press "Submit to
reanalyze", and use the English text at the end of this file. The file facts below
belong to that APK; no field needs filling in.

## Facts already verified locally

| Check | Result |
|---|---|
| Signing certificate (1.5.9 and 1.5.11) | `CN=NexDesk, O=NexDesk, C=IR`, valid 2026-11-09 → 2056-11-01, SHA-256 `CE:F5:4E:21:2E:19:3B:9E:31:E7:54:BB:65:4E:31:24:06:4D:14:BC:78:EA:89:82:B7:6F:0A:86:6C:90:30:88` — a real release key, no `Android Debug` marker anywhere in the APK |
| Nested payloads | none: only `classes.dex` and `classes2.dex`, no embedded `.apk`/`.jar` |
| Sensitive permissions | no SMS, no contacts, no location, no `REQUEST_INSTALL_PACKAGES`, no `QUERY_ALL_PACKAGES` |
| Rendezvous server baked in | `rd.nexdesk.ir` plus the server's Ed25519 public key are present in `libnexdesk.so` |
| Self-identification in system UI | notification title `NexDesk`, channel `NexDesk Service`, virtual display `NexDeskVD` |
| Upstream identity in the binaries (1.5.11+93) | The CI gate for run `44260339337` scanned `classes*.dex`, `libnexdesk.so` and `libapp.so` on all three ABIs for `admin.rustdesk`, `api.rustdesk`, the upstream Ed25519 key `5Qbwsde3…`, the string `RustDesk` and the upstream Dart package name `flutter_hbb`: **zero occurrences**, and the step fails if `libapp.so` is missing. Two things remain and are deliberate: `rustdesk_core_main` (an exported C symbol) and `is_public()`, which recognises the upstream domain in order to switch features **off** for it |
| Account API | resolves to `https://nexdesk.ir`, baked at build time. It previously fell through to `admin.rustdesk.com` and, with a server configured, to `http://<hbbs>:21114` — plain HTTP against a port that serves no web API. No upstream endpoint is reachable or present |
| Control scan (owner-reported) | upstream `rustdesk-1.5.3-universal-signed.apk`, scanned with the same tool, returns `not-a-virus:HEUR:RemoteAdmin.AndroidOS.RustDesk.a` **only** — no `Fakeapp` |
| OpenTip scan of 1.5.11+93 | 2026-11-18 13:06 (databases updated 01:42): 2 detections — 1 Malware, 1 Adware/other — and 0 suspicious activities, 0 network activities, 0 extracted files. Size `78,159,015` B; SHA-256 `699CF3C3F1C5DFBE5D1E964512770F1EED13370109CB17D2C88EE83169237088` |
| Advertising slot | removed in 1.5.11+92: `ad.yar.one`, `document.write` and the dismissal key return zero occurrences in `libapp.so` on all three ABIs. The 1.5.11+93 CI gate re-ran the same scan and passed. Every earlier build contained it, including 85, 90 and 91 |
| Accessibility service | used for touch/key injection into the remote session; the service description is shown by Android before the user can enable it |
| Screen capture | `MediaProjection`, and the system asks for consent on every session |
| Autostart | opt-in and off by default (`KEY_START_ON_BOOT_OPT` defaults to false) |

## Where to send it

1. <https://opentip.kaspersky.com> — upload the APK, then "Submit to reanalyze"
   (or the "I think this file is safe" path). This is the fastest route and it
   returns a case number.
2. If the web form is unavailable: `newvirus@kaspersky.com` with the text below
   and the APK attached (or a download link plus the SHA-256).
3. If Kaspersky removes the detection, open a Bazaar support ticket (ticket or
   021-91009798) quoting the Kaspersky case number and asking for a re-scan of the
   same version code. Bazaar's own malware guide treats the scanner's verdict as
   final until the vendor changes it, so that reply is what unblocks the upload.

## File being submitted

- Name: `NexDesk-1.5.11-android-universal.apk`
- Size: `78,159,015` bytes
- SHA-256: `699CF3C3F1C5DFBE5D1E964512770F1EED13370109CB17D2C88EE83169237088`
- versionName / versionCode: `1.5.11` / `93` (`pubspec.yaml`: `1.5.11+93`)
- Package: `ir.nexdesk.app`
- Source: <https://github.com/vahidkar20/deskyar> (AGPL-3.0 fork of RustDesk)
- Build: Android run `44260339337`, commit `63038e7`; published as a prerelease on
  <https://github.com/vahidkar20/deskyar/releases/tag/v1.5.11-test2>
- OpenTip report:
  <https://opentip.kaspersky.com/699CF3C3F1C5DFBE5D1E964512770F1EED13370109CB17D2C88EE83169237088/results?tab=upload>

Verified on this build: the CI gate for run `44260339337` passed on all three ABIs
(`arm64-v8a`, `armeabi-v7a`, `x86_64`) with zero ad-channel strings and zero
upstream identity strings, including the upstream Dart package name `flutter_hbb`;
the step also fails if `libapp.so` is missing. The OpenTip metadata matches the
size and SHA-256 above.

Tag note: `v1.5.11-test2` points at `63038e7`, the commit that produced this APK.
The older `v1.5.11-test1` tag points at a different tree and is not the source of
this file.

**Upload, do not email.** The APK is 78 MB, above the attachment limit of every
mainstream mail provider (Gmail 25 MB, Outlook ~20 MB). Use the Opentip upload
form; if only email is available, send the SHA-256, the package name and the
release URL above and let Kaspersky pull the file.

## English text for the form / email

> **Subject:** False positive: HEUR:Trojan.AndroidOS.Fakeapp.fm on NexDesk (ir.nexdesk.app)
>
> Hello,
>
> Kaspersky detects our Android application as `HEUR:Trojan.AndroidOS.Fakeapp.fm`.
> We believe this is a false positive and would like to request a reanalysis.
>
> **What the application is.** NexDesk is a free remote-desktop client for
> Windows and Android, published for users in Iran. It is a fork of the
> open-source RustDesk project (GPLv3); the full source, including the Android
> module, is public at https://github.com/vahidkar20/deskyar. It has no in-app
> purchases, no premium-SMS code, no click-fraud code and no hidden payload: the
> APK contains only `classes.dex`, `classes2.dex` and the Flutter/Rust native
> libraries, with no embedded APK or JAR.
>
> **Why the permissions exist.** The app needs
> `BIND_ACCESSIBILITY_SERVICE` to inject touch and keyboard events into the
> remote session, `MediaProjection` to share the screen, and
> `SYSTEM_ALERT_WINDOW` for the optional floating-window control. Every one of
> these is requested by the user from inside the app, is explained on screen,
> and the screen-capture consent dialog is shown by Android for each session.
> Autostart after reboot is an opt-in setting that is off by default.
>
> **Signing.** The APK is signed with our own release certificate
> (SHA-256 CE:F5:4E:21:2E:19:3B:9E:31:E7:54:BB:65:4E:31:24:06:4D:14:BC:78:EA:89:82:B7:6F:0A:86:6C:90:30:88,
> valid until 2056). It is not debug-signed and not repackaged from a
> third-party build.
>
> **Why the heuristic probably fires.** NexDesk is a remote-control client
> carrying a different package name, brand and signing certificate from the
> upstream project while containing its native library. That is also the shape of
> repackaged remote-access trojans, which is presumably what the heuristic is
> reacting to.
>
> **Ten builds, no change in the verdict.** Version 82: boot receiver made
> non-exportable, backup disabled, a debug broadcast action removed. 83: the
> overlay-permission prompt removed from the normal flow. 84: the native library
> renamed `librustdesk.so` -> `libnexdesk.so` and the URI scheme changed. 85: the
> notification title, notification channel and virtual display renamed. 88-91:
> every upstream string removed from the binaries - account API, version feed,
> signing key, and the brand `RustDesk` in 583 places across 54 translation files
> plus the Dart snapshot. 92: the advertising channel removed. 93: the Dart
> package renamed from upstream's `flutter_hbb` to `nexdesk`. Both verdicts came
> back unchanged after every one of them.
>
> Version 92 removed the one capability this fork added to upstream: a live
> advertising slot whose markup a third-party server chose at runtime. That slot
> was present in every build up to and including 91. An earlier draft of this
> document said 86 removed it; that was wrong, and this one does not repeat the
> claim. Version 93 then removed the last upstream package identifier.
>
> **What actually differs from upstream.** Across the 1.5.11 line, the entries
> present in ours and absent there are four Persian font files, one icon, and the
> signature block. Nothing else. Our Rust core and Dart snapshot are both slightly
> smaller than upstream's: this build adds no capability to the RustDesk core, it
> removes some.
>
> **The bytecode shape.** The Android build contains only `classes.dex`,
> `classes2.dex` and the Flutter/Rust native libraries; there is no embedded APK
> or JAR, the app does not load code at runtime or execute a shell, and it does
> not touch SMS.
>
> **Behaviour.** A normal remote-desktop product: the host only accepts
> connections with an ID and password the user configured, and all traffic goes
> to our own server at rd.nexdesk.ir. Version 92 removed the advertising slot;
> version 93 removed the last upstream package identifier. Your own scan of
> version 93 reports zero suspicious activities, zero network activities and
> zero extracted files.
>
> **The same scan already classifies it correctly.** Alongside the `Fakeapp`
> verdict, the product is detected as
> `not-a-virus:HEUR:RemoteAdmin.AndroidOS.RustDesk.a` - your own riskware
> category for remote-administration software, recognising the RustDesk core.
> A binary cannot be both a legitimate remote-admin tool and an app that
> impersonates something else. We are asking for the `Fakeapp` verdict to be
> removed so that only the accurate `RemoteAdmin` classification remains, which
> is how other remote-desktop clients are treated.
>
> The file is attached. Please reanalyse it; we are happy to provide anything
> else you need.
>
> Kind regards,
> NexDesk

## If Kaspersky declines

Do not obfuscate anything to dodge the detector. That is the pattern that turns a
false positive into a real one, and here it is also pointless: the verdict
survived four packaging changes without moving.

Levers that remain, in order of honesty and cost:

1. **Escalate with the vc93 build and the OpenTip report.** A first-line "the
   detection is correct" is the normal answer. The vc93 build is ad-free and
   carries no upstream package identifier; its scan still returns the same two
   detections, and the OpenTip report shows zero suspicious and zero network
   activity. That is the strongest evidence available, and it is already measured.
2. **Myket.** A different store with a different scanner. Worth one upload: it
   does not depend on Kaspersky changing anything, and it restores distribution
   while the ticket is open.
3. **Bazaar manual review.** Ask for a human install-and-inspect review instead
   of a re-scan, quoting the Kaspersky case number. A reviewer can see the
   consent dialogs that a sandbox cannot.

If all of those fail, the honest options are to distribute from the website with a
published SHA-256 and a short note explaining the verdict, or to stop shipping a
RustDesk fork and rebuild the remote core. Everything in between is theatre.
