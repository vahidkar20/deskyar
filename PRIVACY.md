# Privacy

NexDesk is free and funded by advertising. That makes it important to state
exactly what leaves the device, because "it's free" is not by itself a reason to
collect anything.

**Short version:** the client collects no analytics, sends no device or user
identifier to any NexDesk server, and stores no cookies. There are four network
destinations, described below.

## Network requests

### 1. The home-screen ad slot

`GET https://ad.yar.one/`

This is the only advertising request. It carries a single query parameter:

| Parameter | Value | Purpose |
|---|---|---|
| `_` | milliseconds since the epoch | cache-busting, so a proxy does not pin an old creative |

That is the complete request. There is **no** device identifier, install
identifier, user identifier, session token, advertising ID, or hardware
fingerprint, and the client stores no cookies — `package:http` keeps no cookie
jar, so none are sent or persisted.

What the server necessarily sees is what any HTTP request exposes: the source IP
address and the `User-Agent`. That is the same exposure as fetching a web page.

The creative is returned as HTML and parsed natively by
`flutter/lib/desktop/widgets/ad_document.dart`. No web view is embedded, and no
JavaScript is executed — `ad_creative.dart` extracts only the string literal
passed to `document.write` and never evaluates it (`no eval`, `no dart:js`).

The constraint is enforced by `flutter/test/ad_request_anonymity_test.dart`,
which fails the build if any query key other than `_` is introduced.

### 2. An ad click

`GET https://ad.yar.one/click.php?id=<creative number>`

Sent only if the user clicks the creative. The parameter identifies **which ad**
was clicked, not who clicked it. The destination is then opened in the default
browser.

### 3. The update check

`GET https://nexdesk.ir/api/update.php?platform=windows&current=<version>`

Sent 20 seconds after start-up, then every 6 hours. Carries the current version
and platform, plus the `User-Agent` header `NexDesk/<version>`. It is how the
client learns whether a newer release exists; no identifier is attached and the
response is not linked to a device.

The downloaded installer is verified against the SHA-256 published in the
response before it is executed. A mismatch deletes the file.

### 4. The session connection

NexDesk connects to the rendezvous (`hbbs`) and relay (`hbbr`) servers configured
at build time — by default the operator's own, not RustDesk's public
infrastructure. These servers see:

- the device ID, which is derived locally from a hash of the network adapter's
  MAC address and is not transmitted anywhere else;
- connection metadata needed to establish a session (IP addresses, timestamps);
- the session's own traffic, which is end-to-end encrypted and not readable by
  the rendezvous server.

Session content — screen, input, clipboard, transferred files — is not visible to
the server operator.

## What NexDesk does not do

- No analytics or telemetry SDK. `firebase_analytics` is present in
  `flutter/pubspec.yaml` but commented out, and must stay that way: enabling it
  would invalidate the anonymity statement above.
- No crash reporting.
- No device fingerprinting, no persistent client identifier.
- No cookies.
- No advertising network other than the project's own server. There is no
  third-party ad SDK, so no third party receives the request.

## Data stored on the device

Configuration, the device ID and key pair, connection history and the local
option store live in the platform's application data directory. Uninstalling
removes them, except for the copy the portable build extracts to
`%LOCALAPPDATA%\nexdesk`, which is removed by the app's own uninstall action or
manually.

## Changes

If a future version adds any collection — even anonymous aggregate statistics —
this document and the anonymity test must be updated in the same change, and the
change must be called out in the release notes.

## Contact

Questions about this document: <https://nexdesk.ir>
