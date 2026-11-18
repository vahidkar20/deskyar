# Opentip submission — NexDesk false positive

**چکیدهٔ فارسی:** این متن برای ارسال به کسپرسکی (OpenTip) آماده شده. ادعای اصلی ساده است:
ما یک فورک مشروع AGPL از RustDesk هستیم، با گواهی، مخزن و سرور خودمان. تشخیص
`RemoteAdmin.RustDesk.a` درست است و درخواست حذفش را نداریم — موتور همان است.
اما `Fakeapp` باید برداشته شود، چون «ادای برنامهٔ دیگری را درآوردن» توصیف ما نیست.
مهم‌ترین شاهد: تمام رشته‌ها، اندپوینت‌ها، کلید upstream، کانال تبلیغات و حتی نام پکیج Dart
حذف شدند و حکم **تغییر نکرد**؛ گزارش OpenTip نسخهٔ ۹۳ صفر فعالیت مشکوک و صفر فعالیت
شبکه نشان می‌دهد. نتیجهٔ اندازه‌گیری‌شده: تشخیص محتوا-محور نیست. استنباط: به
هویت/شباهت کد موتور واکنش می‌دهد.

---

## Submission text (English — paste into the Opentip form)

### Object

False-positive classification of a legitimate open-source Android application.

### Product

| Field | Value |
|---|---|
| Application | NexDesk — remote desktop |
| Package | `ir.nexdesk.app` |
| Version reported | 1.5.11 (versionCode 93) |
| File | `NexDesk-1.5.11-android-universal.apk` |
| Size | `78,159,015` bytes |
| SHA-256 | `699CF3C3F1C5DFBE5D1E964512770F1EED13370109CB17D2C88EE83169237088` |
| Build | Android run `44260339337`, commit `63038e7` |
| Release | `v1.5.11-test2` (prerelease) |
| Signing certificate | `CN=NexDesk, O=NexDesk, C=IR`, valid 2026-11-09 → 2056-11-01, SHA-256 `CE:F5:4E:21:2E:19:3B:9E:31:E7:54:BB:65:4E:31:24:06:4D:14:BC:78:EA:89:82:B7:6F:0A:86:6C:90:30:88` |
| Source | `https://github.com/vahidkar20/deskyar` (public, full history) |
| Distribution | Google Play and Cafe Bazaar (Iran) |

### Detections

```
Malware                 HEUR:Trojan.AndroidOS.Fakeapp.fm
Adware and other        not-a-virus:HEUR:RemoteAdmin.AndroidOS.RustDesk.a
```

### What this application is

NexDesk is a fork of RustDesk, distributed under AGPL-3.0, which the licence
permits and requires us to do openly. We publish the complete corresponding
source, including every modification, at the URL above. The application connects
to a self-hosted relay (`rd.nexdesk.ir`) that we operate for our own users; it
does not use RustDesk's public infrastructure.

### We accept the second detection

`not-a-virus:HEUR:RemoteAdmin.AndroidOS.RustDesk.a` is **correct**. This is a
remote-administration tool built on the RustDesk engine. The official RustDesk
build receives the same classification. We are not asking for it to be removed:
users should know what the application is capable of.

### We dispute the first detection

`HEUR:Trojan.AndroidOS.Fakeapp.fm` describes an application that impersonates
another application. That is not what this is:

- It does not present itself as RustDesk. The package, label, certificate, URI
  scheme, notification channel and virtual-display name are all NexDesk.
- It does not use RustDesk's servers, update feed, account API or signing keys.
- It does not contain RustDesk's brand, endpoints or key material at all — see
  the measurement below.

### The measurement that matters

We treated the `Fakeapp` verdict as a rebranding defect and removed, one build at
a time, every upstream artefact we could find. On the published 1.5.11+90 APK we
verified by direct byte search over `classes.dex`, `classes2.dex`,
`lib/arm64-v8a/libnexdesk.so` and `lib/arm64-v8a/libapp.so`:

| Pattern | Occurrences |
|---|---|
| `admin.rustdesk` (upstream account API) | 0 |
| `api.rustdesk` (upstream version feed) | 0 |
| `5Qbwsde3…` (upstream Ed25519 key) | 0 |
| `RustDesk` (the brand, any context) | 0 |
| `com.carriez` (upstream package prefix) | 0 |

Four earlier builds changed only packaging and branding: notification strings,
the native library name, the URI scheme and a boot receiver. **Every one of those
returned a byte-identical verdict.**

Version 92 removed the one capability this fork added: a live advertising slot
whose markup a third-party server chose at runtime. It was present in every build
up to and including 91; an earlier draft of this submission claimed version 86
removed it, and that claim was false. Version 92 was the first build without it.
Version 93 then renamed the Dart package from upstream's `flutter_hbb` to
`nexdesk` and changed the generated share link to `nexdesk://`.

The CI gate for the version-93 build scans every `libapp.so`, `libnexdesk.so` and
`classes*.dex` for the ad strings, the upstream endpoints, the upstream key, the
brand and `flutter_hbb`, and fails if `libapp.so` is missing. It passed on all
three ABIs.

**Both version 92 and version 93 were scanned, and both returned the same two
detections.** The OpenTip report for version 93 (scanned 2026-11-18 13:06,
databases updated 01:42) lists two detections — one Malware, one Adware/other —
and zero suspicious activities, zero network activities and zero extracted files.

That is the point of this submission, stated precisely: every content-level
difference we could remove has been removed, and the verdict did not move. On the
measurement, `Fakeapp` is not reachable from the package. The remaining signal is
the identity of the RustDesk engine under a different certificate; that is an
inference, not something we can prove from outside. We are not predicting that a
reanalysis will change the verdict. We are asking for it to be looked at, and for
the trigger to be named if it is identity.

### What we are asking

Either of the following would resolve this:

1. **Reclassify** this package, on the basis that it is an openly published
   AGPL fork with its own certificate, package identity and infrastructure, and
   that its behaviour matches `RemoteAdmin` and nothing more.
2. **Tell us which signal triggers `Fakeapp`.** If it is the code similarity to
   RustDesk — which we cannot change without rewriting the engine, and which the
   licence expressly permits us not to — then we will stop trying to engineer
   around it and pursue the first option only.

### Supporting material

- Source, full history and release artefacts: `https://github.com/vahidkar20/deskyar`
- The exact file:
  `https://github.com/vahidkar20/deskyar/releases/download/v1.5.11-test2/NexDesk-1.5.11-android-universal.apk`
  (SHA-256 `699CF3C3F1C5DFBE5D1E964512770F1EED13370109CB17D2C88EE83169237088`)
- Build: Android run `44260339337`, commit `63038e7`
- OpenTip report for this hash:
  `https://opentip.kaspersky.com/699CF3C3F1C5DFBE5D1E964512770F1EED13370109CB17D2C88EE83169237088/results?tab=upload`
- Our own analysis, including the control scan of the official RustDesk APK
  (which returns `RemoteAdmin` only, with no `Fakeapp`):
  `docs/kaspersky-false-positive.md` in that repository.
- The application requests accessibility and screen-capture permissions, both
  gated by explicit Android consent prompts, as any remote-support tool must.

### Contact

`info@nexdesk.ir`

---

## Notes for the owner (not for submission)

**۱. این را با نسخهٔ ۹۳ بفرستید.** فایل و SHA باید یکی باشند:
`699CF3C3F1C5DFBE5D1E964512770F1EED13370109CB17D2C88EE83169237088`. فایل در
ریلیز `v1.5.11-test2` است. در OpenTip روی همان گزارش، «Submit to reanalyze» را
بزنید و متن انگلیسی بالا را در توضیحات بچسبانید.

**۲. فایل را ضمیمه کنید، نه لینک.** بازبین به لینک دانلود دسترسی ندارد؛ اگر فرم
آپلود جدا دارد، همان APK را بدهید.

**۳. انتظار واقع‌بینانه (تجربهٔ قبلی، نه پیش‌بینی):** پاسخ معمول چند روز کاری است.
دو حالت ممکن:
- **می‌پذیرند** → حکم روی همان فایل برداشته می‌شود؛ برای نسخهٔ بعدی باید دوباره
  بررسی شود، ولی سابقهٔ ناشر ساخته می‌شود.
- **رد می‌کنند** → جواب همان است که گفتم: `Fakeapp` ذاتیِ فورک است. آن‌وقت تصمیم
  تجاری می‌شود، نه فنی.

**۴. چیزی که نباید بنویسید:** «این یک باگ کسپرسکی است». حتی اگر باشد، لحن درخواست را
خراب می‌کند. متن بالا عمداً می‌گوید تشخیص `RemoteAdmin` را می‌پذیریم — این اعتماد می‌سازد.

**۵. اگر پرسیدند چرا گواهی عوض شده:** چون محصول و ناشر عوض شده. گواهی از نسخهٔ ۱.۵.۹
تا امروز یکی است و تغییر نکرده — این را می‌توانید ثابت کنید.

**۶. متن تیکت بازار (بعد از ثبت درخواست کسپرسکی):**

> سلام،
> نسخهٔ ۱.۵.۱۱ (versionCode 93) اپلیکیشن NexDesk با بستهٔ `ir.nexdesk.app` را برای
> بررسی ارسال کرده‌ایم. اسکنر کسپرسکی دو تشخیص می‌دهد: `RemoteAdmin.AndroidOS.RustDesk.a`
> که برای یک ابزار ریموت‌دسکتاپ مبتنی بر RustDesk درست است، و `Fakeapp.fm` که
> نادرست است. درخواست بازبینی در OpenTip ثبت شد.
> گزارش OpenTip برای همین فایل: ۲ تشخیص، صفر فعالیت مشکوک، صفر فعالیت شبکه، صفر
> فایل استخراج‌شده. SHA-256: `699CF3C3F1C5DFBE5D1E964512770F1EED13370109CB17D2C88EE83169237088`.
> سورس کامل: `https://github.com/vahidkar20/deskyar`.
> خواهشمندیم همین versionCode را بازبینی انسانی/اسکن مجدد کنید و نتیجه را اعلام کنید.
