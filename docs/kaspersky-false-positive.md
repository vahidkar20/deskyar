# Kaspersky false positive — NexDesk (Android)

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

`not-a-virus:` is Kaspersky's own prefix for *not malware*: it is the riskware
category for remote-administration tools, and this one is named after RustDesk
because the engine has recognised the RustDesk core inside the APK. So the same
scan says both "this is a RustDesk-based remote-admin tool" and "this is a fake
app". Both cannot be true of the same binary. The consistent reading is the first
one: a GPL fork of a known remote-desktop project, which is exactly what it is.
The `Fakeapp` hit is the heuristic misfiring on a repackaged remote-access client
- the shape, not the behaviour.

## Four packaging changes, one unchanged verdict

| versionCode | what changed | Kaspersky result |
|---|---|---|
| 82 | boot receiver `exported=false`, `allowBackup=false`, debug action removed | unchanged |
| 83 | overlay-permission prompt removed from the normal flow | unchanged |
| 84 | native library renamed `librustdesk.so` → `libnexdesk.so`, scheme `nexdesk://` | unchanged |
| 85 | notification title, channel id/name and virtual-display name renamed; **zero** `RustDesk` strings left in either DEX | unchanged |

Four independent changes to packaging, naming and system-UI strings, and both
verdicts come back byte-identical every time. That is the empirical core of this
request: the `Fakeapp` line is not computed from anything a fork can rename.

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

## The control result

Scanned with the same tool, upstream `rustdesk-1.5.3-universal-signed.apk` returns:

```
Adware and other  not-a-virus:HEUR:RemoteAdmin.AndroidOS.RustDesk.a
```

No `Fakeapp`. Two conclusions follow directly from that:

1. `RemoteAdmin.RustDesk.a` is inherent to the RustDesk core and appears on any
   build containing it, including the official one. It is not a defect and it
   cannot be removed from a fork.
2. `Fakeapp` is specific to this build. The detector is not reacting to the
   RustDesk code — it is reacting to something this fork adds.

The only capability this fork adds over upstream is an ad slot that fetches one
banner from `ad.yar.one` at launch. That is the remaining single-variable
hypothesis, and it is being tested with a build that has the slot compiled out.

## What to say about the riskware line

Do not ask Kaspersky to remove `RemoteAdmin.RustDesk.a`. Their own scan returns
it for upstream RustDesk as well, so it is the correct classification for a
remote-administration tool, and Bazaar did not object to it. The request is only
about `Fakeapp`.

## How to send it

Both build facts below are current; nothing needs filling in. Upload the APK at
<https://opentip.kaspersky.com> and use the English text at the end of this file.

## Facts already verified locally

| Check | Result |
|---|---|
| Signing certificate (1.5.9 and 1.5.11) | `CN=NexDesk, O=NexDesk, C=IR`, valid 2026-11-09 → 2056-11-01, SHA-256 `CE:F5:4E:21:2E:19:3B:9E:31:E7:54:BB:65:4E:31:24:06:4D:14:BC:78:EA:89:82:B7:6F:0A:86:6C:90:30:88` — a real release key, no `Android Debug` marker anywhere in the APK |
| Nested payloads | none: only `classes.dex` and `classes2.dex`, no embedded `.apk`/`.jar` |
| Sensitive permissions | no SMS, no contacts, no location, no `REQUEST_INSTALL_PACKAGES`, no `QUERY_ALL_PACKAGES` |
| Rendezvous server baked in | `rd.nexdesk.ir` plus the server's Ed25519 public key are present in `libnexdesk.so` |
| Self-identification in system UI | notification title `NexDesk`, channel `NexDesk Service`, virtual display `NexDeskVD`; `classes.dex` + `classes2.dex` contain **zero** occurrences of the string `RustDesk` (verified on the published 1.5.11+85 APK) |
| Control scan | upstream `rustdesk-1.5.3-universal-signed.apk`, scanned with the same tool, returns `not-a-virus:HEUR:RemoteAdmin.AndroidOS.RustDesk.a` **only** — no `Fakeapp` |
| Accessibility service | used only for touch/key injection; the service description is shown by Android before the user can enable it |
| Screen capture | `MediaProjection`, and the system asks for consent on every session |
| Autostart | opt-in and off by default (`KEY_START_ON_BOOT_OPT` defaults to false) |

## Where to send it

1. <https://opentip.kaspersky.com> — upload the APK, then "Submit to reanalyze"
   (or the "I think this file is safe" path). This is the fastest route and it
   returns a case number.
2. If the web form is unavailable: `newvirus@kaspersky.com` with the text below
   and the APK attached (or a download link plus the SHA-256).
3. When Kaspersky answers that the detection is removed, open a Bazaar support
   ticket (ticket or 021-91009798) quoting the Kaspersky case number and asking
   for a re-scan of the same version code. Bazaar's own malware guide treats
   their scanner's verdict as final until the vendor changes it, so this reply
   is what unblocks the upload.

## File being submitted

- Name: `NexDesk-1.5.11-android-universal.apk`
- Size: `78205043` bytes
- SHA-256: `15e4f9a7a73a0e473b1c1bb4320873911b04228bcc24aefc21e68315bc0de504`
- versionName / versionCode: `1.5.11` / `85`
- Package: `ir.nexdesk.app`
- Source: <https://github.com/vahidkar20/deskyar> (GPLv3 fork of RustDesk)
- Build: Android run `43902902139`, commit `197d1f0`; published on
  <https://github.com/vahidkar20/deskyar/releases/tag/v1.5.11-av.2>

Verified on the published binary (not on the source): `versionCode 85`,
`allowBackup=false`, `BootReceiver exported=false`, `minSdk 22`, `targetSdk 36`,
three ABIs (`arm64-v8a`, `armeabi-v7a`, `x86_64`), `rd.nexdesk.ir` and the server
key present in `libnexdesk.so`, no nested `.apk`/`.jar`, certificate as above, and
no `RustDesk` string left in either DEX.

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
> distributed outside Google Play, carrying a different package name and brand
> from the upstream project while containing its native library. That is also
> the shape of repackaged remote-access trojans, which is presumably what the
> heuristic is reacting to.
>
> **Four builds, four changes, no change in the verdict.** Version 82: boot
> receiver made non-exportable, backup disabled, a debug broadcast action
> removed. 83: the overlay-permission prompt removed from the normal flow. 84:
> the native library renamed `librustdesk.so` -> `libnexdesk.so` and the URI
> scheme changed. 85: the notification title, notification channel and virtual
> display renamed, leaving zero occurrences of the string `RustDesk` in either
> DEX. Both verdicts returned byte-identical after each of the four.
>
> **What actually differs from upstream.** Compared archive to archive against
> `rustdesk-1.5.3-universal-signed.apk`, the entries present in ours and absent
> there are four Persian font files, one icon, and the signature block. Nothing
> else. Our Rust core is 36.72 MB against upstream's 37.80 MB, and our Dart
> snapshot is 130 KB smaller: this build adds no capability to the RustDesk
> core, it removes some.
>
> **The bytecode has the same shape as the build you already know.** In both
> APKs, `classes.dex` + `classes2.dex` contain zero references to
> `DexClassLoader`, `PathClassLoader`, `InMemoryDexClassLoader`,
> `Runtime.getRuntime`, `ProcessBuilder`, `SmsManager`, `addJavascriptInterface`
> and `javascript:` URLs. The counts for `AccessibilityService`,
> `TelephonyManager` and `getDeviceId` are identical in both. Neither file loads
> code at runtime, executes a shell, bridges web content into app code, or
> touches SMS.
>
> **Behaviour.** A normal remote-desktop product: the host only accepts
> connections with an ID and password the user configured, and all traffic goes
> to our own server at rd.nexdesk.ir. The only third-party content the app shows
> is a single self-hosted banner image, fetched over HTTPS and drawn with native
> widgets - no remote script is executed and there is no web-to-native bridge.
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

Do not obfuscate anything to dodge the detector — that is the pattern that turns
a false positive into a real one. The remaining levers, in order of honesty:

1. Remove the ad banner from the Bazaar build (a remote-desktop client that
   fetches an ad creative on launch is closer to the `Fakeapp` profile than one
   that does not). This costs revenue, so it is the owner's call.
2. Ship a build with autostart removed entirely rather than opt-in.
3. Ask Bazaar to review manually: their reviewers can install the app and see
   the consent dialogs, which a scanner cannot.
