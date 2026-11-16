# Kaspersky false positive — NexDesk (Android)

Cafe Bazaar rejected the upload with:

> version code: 79, cpu architecture: arm64-v8a, armeabi-v7a
> بسته بارگذاری شده توسط «سپر امنیت بازار» بررسی شده است و توسط آنتی‌ویروس(های)
> «Kaspersky» به عنوان بدافزار «HEUR:Trojan.AndroidOS.Fakeapp.fm» شناخته شده است.

`HEUR:` means a heuristic verdict, not a signature match. The `Fakeapp` family in
Kaspersky's encyclopedia is described as apps that masquerade as popular apps and
run premium-SMS/ad fraud. None of that exists in this app; the detector is
scoring the *shape* of a remote-desktop client that ships as a fork.

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

This file is the evidence package for the reanalysis request. Fill in the two
`TODO` values from the build being submitted, then send it.

## Facts already verified locally

| Check | Result |
|---|---|
| Signing certificate (1.5.9 and 1.5.11) | `CN=NexDesk, O=NexDesk, C=IR`, valid 2026-11-09 → 2056-11-01, SHA-256 `CE:F5:4E:21:2E:19:3B:9E:31:E7:54:BB:65:4E:31:24:06:4D:14:BC:78:EA:89:82:B7:6F:0A:86:6C:90:30:88` — a real release key, no `Android Debug` marker anywhere in the APK |
| Nested payloads | none: only `classes.dex` and `classes2.dex`, no embedded `.apk`/`.jar` |
| Sensitive permissions | no SMS, no contacts, no location, no `REQUEST_INSTALL_PACKAGES`, no `QUERY_ALL_PACKAGES` |
| Rendezvous server baked in | `rd.nexdesk.ir` plus the server's Ed25519 public key are present in `librustdesk.so` |
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
- Size: `78204943` bytes
- SHA-256: `8dd02a0dd16b1dce7a0ff0b2500b1e7666f43d9b7540eb213558c90f88d43dd1`
- versionName / versionCode: `1.5.11` / `84`
- Package: `ir.nexdesk.app`
- Source: <https://github.com/vahidkar20/deskyar> (GPLv3 fork of RustDesk)
- Build: Android run `43892881827`, commit `9472eeb`; published on
  <https://github.com/vahidkar20/deskyar/releases/tag/v1.5.11-av.1>

Verified on the published binary (not on the source): `versionCode 84`,
`allowBackup=false`, `BootReceiver exported=false`, three ABIs
(`arm64-v8a`, `armeabi-v7a`, `x86_64`), `rd.nexdesk.ir` and the server key present
in `librustdesk.so`, no nested `.apk`/`.jar`, certificate as above.

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
> heuristic is reacting to. The behaviour, however, is a normal remote-desktop
> product: the host only accepts connections with an ID and password that the
> user configured, and all traffic goes to our own server at rd.nexdesk.ir.
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
