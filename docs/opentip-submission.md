# Opentip submission — NexDesk false positive

**چکیدهٔ فارسی:** این متن برای ارسال به کسپرسکی (opentip) آماده شده. ادعای اصلی ساده است:
ما یک فورک مشروع AGPL از RustDesk هستیم، با گواهی و مخزن و سرور خودمان. تشخیص
`RemoteAdmin.RustDesk.a` درست است و آن را نمی‌پذیریم که حذف شود — موتور همان است.
اما `Fakeapp` باید برداشته شود، چون «ادای برنامهٔ دیگری را درآوردن» توصیف ما نیست.
مهم‌ترین شاهد: ما تمام رشته‌ها، اندپوینت‌ها و کلید upstream را حذف کردیم و حکم **تغییر نکرد** —
یعنی تشخیص محتوا-محور نیست.

---

## Submission text (English — paste into the Opentip form)

### Object

False-positive classification of a legitimate open-source Android application.

### Product

| Field | Value |
|---|---|
| Application | NexDesk — remote desktop |
| Package | `ir.nexdesk.app` |
| Version reported | 1.5.11 (versionCode 92) |
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

Version 92 makes the one change that is not cosmetic. The fork had added a live
advertising slot: the home pane fetched a third-party page and parsed its markup
into native widgets. It was present in every build up to and including 91 — an
earlier draft of this submission claimed version 86 removed it, and that claim was
false. Version 92 is the first build without it.

That is the point of this submission, stated precisely: four packaging changes did
not move the verdict, and the one behavioural difference is now gone. If the
verdict survives version 92, the `Fakeapp` classification is not reachable from
anything in the package, and we have no further means to address it from our side.
We are not claiming it will change; we are asking for it to be looked at.

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
- Our own analysis, including the control scan of the official RustDesk APK
  (which returns `RemoteAdmin` only, with no `Fakeapp`):
  `docs/kaspersky-false-positive.md` in that repository.
- The application requests accessibility and screen-capture permissions, both
  gated by explicit Android consent prompts, as any remote-support tool must.

### Contact

`info@nexdesk.ir`

---

## Notes for the owner (not for submission)

**۱. این را با نسخهٔ ۹۱ بفرستید، نه ۹۰.** تفاوتشان دو رشتهٔ متنی است؛ ولی عدد باید با
فایلی که ضمیمه می‌کنید یکی باشد.

**۲. فایل را ضمیمه کنید، نه لینک.** بازبین به لینک دانلود دسترسی ندارد.

**۳. انتظار واقع‌بینانه:** پاسخ معمول ۳ تا ۱۰ روز کاری است. دو حالت ممکن:
- **می‌پذیرند** → حکم روی امضای همان فایل برداشته می‌شود. برای هر نسخهٔ بعدی باید
  دوباره بررسی شود، ولی سابقهٔ ناشر ساخته می‌شود.
- **رد می‌کنند** → جواب همان است که گفتم: `Fakeapp` ذاتیِ فورک است. آن‌وقت تصمیم
  تجاری می‌شود، نه فنی.

**۴. چیزی که نباید بنویسید:** «این یک باگ کسپرسکی است». حتی اگر باشد، لحن درخواست را
خراب می‌کند. متن بالا عمداً می‌گوید تشخیص `RemoteAdmin` را می‌پذیریم — این اعتماد می‌سازد.

**۵. اگر پرسیدند چرا گواهی عوض شده:** چون محصول و ناشر عوض شده. گواهی از نسخهٔ ۱.۵.۹
تا امروز یکی است و تغییر نکرده — این را می‌توانید ثابت کنید.
