# Privacy policy

NexDesk does not have an account system and does not collect analytics. This
document lists every outbound connection the application makes on its own
initiative, so you can check the claim against the source.

## The advertising request

The home screen shows one advertising slot; the mobile app shows a dismissible
banner. Loading it issues:

```
GET https://ad.yar.one/?_=<unix timestamp>
```

Nothing else is sent. Specifically, the request carries **no** device
identifier, install identifier, user identifier, version number, locale,
platform, screen size, or session information. The single parameter exists to
defeat HTTP caching. There is no third-party ad SDK, no WebView, and no
JavaScript executed from the ad response.

Closing the ad stops further requests.

## Update checks

```
GET https://nexdesk.ir/api/update.php?platform=<os>&current=<version>
```

The response tells the client whether a newer version exists, where to download
it, and its SHA-256. No identifier is sent, so update checks cannot be correlated
into an install base.

## Remote desktop connections

A session is established through the rendezvous/relay server configured at build
time (`NEXDESK_SERVER`, default `rd.nexdesk.ir`), or through a server you run
yourself. Session traffic is end-to-end encrypted between the two peers.

The server sees connection metadata — peer IDs, IP addresses, timestamps — as any
relay must. It does not see session content.

## What is stored locally

Configuration, peer IDs, and logs are stored under `%APPDATA%\NexDesk` (or the
platform equivalent). Uninstalling removes them; the portable build keeps them
next to the extracted payload.

## Third-party components

NexDesk is built on RustDesk and other open source components, each with its own
project. Those components do not make network requests on NexDesk's behalf beyond
what is described above.

## Contact

Questions about this policy: **info@nexdesk.ir**.
