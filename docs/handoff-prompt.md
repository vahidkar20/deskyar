# Handoff prompt — NexDesk / Cafe Bazaar false positive

**راهنمای استفاده (برای مالک):** کل بخش زیر خط جداکننده را کپی کنید و به هوش مصنوعی
جدید بدهید. خودبسنده است — آن هوش مصنوعی هیچ‌چیز از گفتگوی ما نمی‌داند. نتیجهٔ اسکن
vc92، vc93 و 1.5.12 در همین سند ثبت شده است.

---

You are taking over an ongoing task on a real, shipping product. Read this whole
brief before doing anything. Much of it is corrections to things that were
believed earlier and turned out to be false — do not re-derive them from the
repository's documents alone, because some of those documents were wrong and were
only recently fixed.

## 1. The product

**NexDesk** is an Android/Windows remote-desktop application, a rebranded fork of
RustDesk (AGPL-3.0). Package `ir.nexdesk.app`, publisher `NexDesk`, Iran.

- Repository: `D:/Dehghani/Rust Desk github/deskyar`, branch `feat/native-installer`
- Rendezvous server: `rd.nexdesk.ir` (self-hosted, baked at build time)
- Account API: `https://nexdesk.ir` (baked at build time)
- Current build: versionCode **94**, versionName 1.5.12

The owner distributes through Google Play and wants to distribute through **Cafe
Bazaar**, the major Iranian Android store. Bazaar refuses the app.

## 2. The problem, stated precisely

Kaspersky's engine (which Bazaar uses) returns **two** detections:

```
Malware            HEUR:Trojan.AndroidOS.Fakeapp.fm
Adware and other   not-a-virus:HEUR:RemoteAdmin.AndroidOS.RustDesk.a
```

**These are not the same problem, and conflating them wastes weeks.**

- `RemoteAdmin.AndroidOS.RustDesk.a` is **correct and permanent**. It says "this
  is a remote-administration tool built on the RustDesk engine". That is literally
  what the product is. The official RustDesk APK gets the same verdict. It cannot
  be removed without rewriting the remote-desktop engine, and it is not what Bazaar
  objects to. **Do not try to remove it. Do not dispute it in any submission.**
- `HEUR:Trojan.AndroidOS.Fakeapp.fm` is the disputed one. It alleges the app
  impersonates another app. That is the claim to fight.

## 3. What has already been tried, and what it proved

The work proceeded in controlled steps, each scanned by the owner:

| versionCode | what changed | verdict |
|---|---|---|
| 82–85 | packaging and branding: boot receiver, overlay prompt, native library rename, notification strings, URI scheme | **unchanged** |
| 88–91 | every upstream string removed from the binaries: upstream account API, upstream version feed, upstream Ed25519 signing key, the brand `RustDesk` in 583 places across 54 translation files, the Dart snapshot, the custom-client loader | **unchanged** |
| 92 | the live advertising channel removed — see below | **unchanged** |
| 93 | the Dart package renamed `flutter_hbb` → `nexdesk`; share links `nexdesk://` | **unchanged** (OpenTip, 2026-11-18) |
| 94 (1.5.12) | the ad channel restored at the owner's request; final stable | **unchanged** (OpenTip, 2026-11-18 15:04) |

Verified by direct byte search on the published APKs: at vc90 and vc91 the DEX and
both native libraries contained **zero** occurrences of `admin.rustdesk`,
`api.rustdesk`, `5Qbwsde3…` (upstream's key) and `RustDesk`. The verdict did not
move.

**Conclusion already established:** the `Fakeapp` detection is not reachable from
the content of the package. Do not spend effort on further string scrubbing.

## 4. The one real finding, and the current state

An audit on 2026-11-17 found that a **live advertising channel had been present in
every build ever shipped**, while the project's own documentation claimed it was
removed at vc86. Verified: `ad.yar.one` and `document.write` were in `libapp.so` at
vc85, vc90 and vc91.

That slot was the only part of the app whose content a third-party server chose at
runtime — the home pane fetched an ad page, followed up to three `<script src>`
tags, parsed the `document.write` literals into native widgets, and rendered them.
In a process that holds the user's remote session, that is an unbounded capability.

It was removed in vc92 (four files, 1672 lines, both mount points, the 5-minute
refresh timer, the dismissal key, and two Persian ad strings that were shipping
inside `libnexdesk.so`).

**vc92, vc93 and the final 1.5.12 have all been scanned; every verdict is unchanged.**

```
tag      v1.5.11-test1   (prerelease, vc92)
sha256   1de1eeba25dd91d2aa146898a40d6a68dade0d255404c2cd4f3c429a299086a9

tag      v1.5.11-test2   (prerelease, vc93, commit 63038e7)
sha256   699cf3c3f1c5dfbe5d1e964512770f1eed13370109cb17d2c88ee83169237088

tag      v1.5.12-final   (stable, vc94; tag commit fac5de6, APK from db63dea)
sha256   974a351c00160b7c2f9f9974a0d8628803aac627a4ef6faf4ebad8a6bf4c5879
```

OpenTip for vc93 (2026-11-18 13:06, databases 01:42): 2 detections (1 Malware,
1 Adware/other), 0 suspicious activities, 0 network activities, 0 extracted
files.

OpenTip for 1.5.12 (2026-11-18 15:04, databases 09:42): the same 2 detections
and the same zero suspicious/network/extracted counts, with the ad channel
restored.

Verified on the vc92 APK: `ad.yar.one`, `document.write` and
`nexdesk-mobile-banner-dismissed` return **zero** occurrences in the DEX,
`libnexdesk.so`, and `libapp.so` on all three ABIs. The code symbols confirm it:
`NexDeskBanner` 2→0, `resolveAdCreative` 1→0, `ad_creative` 1→0. The vc93 CI gate
re-ran the ad and upstream-identity scans (including `flutter_hbb`) and passed on
all three ABIs. The 1.5.12 gate removed the ad check because the ad channel is
restored; the upstream-identity gate still passed on all three ABIs.

## 5. Your first action

The vc93 and 1.5.12 scans are done; both verdicts are unchanged. The next action is
the vendor submission: send `docs/opentip-submission.md` to OpenTip with the
1.5.12 APK, then open the Bazaar ticket. Do not start new engineering before
Kaspersky answers.

**Measured result:** the ad-free vc93 build and the ad-present 1.5.12 build both
return the same two detections, with zero suspicious/network activity and zero
extracted files. The consistent reading is that `Fakeapp` tracks **identity** —
RustDesk machine code under a different certificate — not behaviour or the ad
slot. That last part is an inference from the measurement, not a separate scan.

The remaining path is the vendor conversation; further code changes have near-zero
expected value. Tell the owner that plainly.

## 6. Hard-won constraints — violating these wastes days

1. **Scan the whole APK, not the files you believe are relevant.** Five targeted
   scans missed the ad channel; one `zipfile` sweep over all 498 entries found it in
   seconds.
2. **A gate that matches nothing passes silently.** The CI gate unpacked
   `libapp.so` and then only globbed `libnexdesk.so` and the DEX. The file was on
   disk and never read, which manufactured confidence for five releases. Any new
   gate must assert the artefact exists before trusting a zero.
3. **Do not use file size as a proxy for a Dart change.** Removing 1672 lines left
   `libapp.so` byte-identical in size (12,387,232) while 2,988 of 3,025 4KB blocks
   differed. Compare hashes and symbols.
4. **`libapp.so` is at `lib/<abi>/libapp.so`**, not in `assets/`. It is the Dart AOT
   snapshot shipped as a shared library.
5. **Never predict the verdict in a document.** Two documents go to third parties
   who can verify claims: `docs/kaspersky-false-positive.md` (the vendor) and
   `docs/signpath-application.md` (a code-signing authority). Both previously
   contained assertions that were false, including a citation to a test file that
   has never existed. Read them, but verify every factual claim against the code
   before reusing it.
6. **Do not obfuscate, pack, or hide anything to dodge the detector.** That converts
   a false positive into a true one.
7. `is_custom_client()` and `is_public()` deliberately contain the literal
   `"RustDesk"` / the upstream domain — they must name upstream to recognise it and
   switch features off. Do not "clean" these.

## 7. Facts you will need

- **Build:** GitHub Actions, `.github/workflows/nexdesk-android.yml`, `workflow_dispatch`
  with input `make_release: "false"`. Takes ~35 minutes. A gate step after the APK
  build fails the run if forbidden strings are present.
- **Publish:** `.github/workflows/publish-release.yml`, inputs `tag`, `windows_run`,
  `android_run`, `prerelease`, `title`.
- **Current gate patterns:** upstream identity
  `admin\.rustdesk|api\.rustdesk|5Qbwsde3|RustDesk`; ad channel
  `ad\.yar\.one|document\.write|nexdesk-mobile-banner-dismissed`.
- **Signing certificate:** `CN=NexDesk, O=NexDesk, C=IR`, SHA-256
  `CE:F5:4E:21:2E:19:3B:9E:31:E7:54:BB:65:4E:31:24:06:4D:14:BC:78:EA:89:82:B7:6F:0A:86:6C:90:30:88`.
  Unchanged across releases; verify it stays that way.
- **Deliberately kept, do not "fix":** `rustdesk_core_main` (an exported C symbol
  used by the Windows and Linux runners), `rustdesk_idd` (must match the installed
  IDD driver), `is_public()`'s upstream domain match (a deny-rule).

## 8. Documents in the repository

| File | Purpose | Trust |
|---|---|---|
| `docs/opentip-submission.md` | the vendor submission, ready to send | corrected 2026-11-17; verify before sending |
| `docs/kaspersky-false-positive.md` | the evidence dossier behind it | corrected; the historical claims were once false |
| `docs/nexdesk-account-api.md` | **for a different team** — the website team implementing login on nexdesk.ir. Standalone, complete, not part of this problem. |
| `docs/signpath-application.md` | application to SignPath for free code signing | corrected; contained a fabricated test citation |
| `PRIVACY.md` | outbound connections | corrected |

## 9. Open items, ranked by value

1. **Send the Opentip submission for 1.5.12** — the only mechanism that can change
   the verdict. `docs/opentip-submission.md` is written to be sent. Attach the
   APK; a reviewer cannot download from a link. SHA-256 `974A…5879`.
2. **Bazaar ticket** — after the Kaspersky request, open a ticket asking for a
   human review/re-scan of 1.5.12 (versionCode 94), quoting the OpenTip report.
3. **`InputService.kt:634`** logs the focused text field's contents to logcat during
   input injection. Inherited from upstream, never persisted, but it is literally
   "intercept keyboard input" — the phrase in Kaspersky's generic Trojan description.
   A one-line fix with no product impact. Not yet done.
4. **Windows half of the purge** — `librustdesk.dll`, `RustDeskIddDriver`,
   `RustDesk v4 Printer Driver`. Each needs a Windows build and carries MSI risk.
   None affects the Android verdict.
5. **Crate rename** (`[lib] name = "librustdesk"` → `"nexdesk"`) would remove ~100
   `librustdesk::` log-target strings from the native library. It was deliberately
   **not** done: it cannot move the verdict and it touches the Windows and Linux
   startup paths, which cannot be tested locally. Only do it if the owner accepts
   that risk explicitly.

## 10. How to talk to the owner

They are technical, they read the evidence, and they have been given optimistic
predictions before that did not hold. State what is measured and what is inferred,
separately. If a previous claim turns out to be wrong, say so directly and correct
the artefact — they will trust the correction more than a hedge.

Do not promise that any change will change the verdict. The honest position is:
the remaining lever is the vendor, not the code.
