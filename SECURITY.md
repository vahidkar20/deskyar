# Security policy

## Reporting a vulnerability

Please **do not** open a public issue for a security problem.

Report it privately using the contact address published on
<https://nexdesk.ir>, with:

- the affected component and version (`NexDesk → About` shows both);
- what an attacker gains, and the preconditions;
- reproduction steps, and a proof of concept if you have one.

You will get an acknowledgement, an assessment, and — if the report is valid — a
fix and a release note that credits you unless you prefer otherwise. Please allow
time for a fix before publishing details.

## Supported versions

Only the latest release receives security fixes. The client checks for updates
every 6 hours; a build more than one minor version behind is considered
unsupported.

## Threat model

NexDesk is a remote-access tool, so the interesting adversaries are:

**Someone who wants to control a device they do not own.** The relevant
safeguards are that the controlled side must accept the incoming session, that a
connection indicator is visible for the duration of the session, and that
unattended access requires the device owner to set a permanent password. A
session cannot be started against a device whose owner has not enabled access.

**Someone on the network path.** Session traffic is end-to-end encrypted between
the two peers; the rendezvous and relay servers forward ciphertext and cannot
read screen content, input, clipboard or transferred files. The server's identity
is pinned at build time through the public key baked in from
`NEXDESK_SERVER_KEY`, so a substituted server fails verification.

**Someone who can tamper with a download.** Release artifacts are
Authenticode-signed with a timestamp, and the updater additionally verifies the
installer's SHA-256 and exact byte size against the signed update response before
running it. A mismatch deletes the file.

**Someone who can tamper with the ad creative.** The ad slot parses HTML and
renders layout blocks natively; it does not execute JavaScript and does not embed
a browser engine. See [PRIVACY.md](PRIVACY.md).

### Out of scope

- Attacks that require an already-compromised device or an administrator account.
- Denial of service against a self-hosted rendezvous server.
- Physical access.
- The behaviour of third-party dependencies with no NexDesk-specific
  configuration; report those upstream, but tell us if NexDesk's use of them is
  unsafe.

## Abuse

NexDesk must not be used to access a device without its owner's authorisation.
If you believe a NexDesk session is being used against you:

1. Disconnect the machine from the network.
2. Remove NexDesk (Settings → Apps, or the app's own uninstall action), and
   change the permanent password if one was set.
3. Report it through <https://nexdesk.ir> with the device ID shown in the app
   before removal, and any timestamp you have.

Reports of abuse are reviewed; a device ID involved in confirmed abuse is blocked
from the rendezvous service.

## Scope of this repository

This repository contains the client, the portable packer and the MSI packaging.
The rendezvous and relay servers (`hbbs` / `hbbr`) are deployed separately and
are not built from here; vulnerabilities in the server should be reported to the
upstream RustDesk project unless the issue is specific to this deployment.
