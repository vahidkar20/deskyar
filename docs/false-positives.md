# Antivirus false positives

Windows Defender and other engines periodically flag NexDesk. This file records
what was submitted, when, and what came back — partly so a repeat detection can
be answered with the previous ticket, and partly because a documented
false-positive process is evidence of good faith if a code-signing or store
review asks how abuse is handled.

## Why this happens

A signature is not what stops an engine from flagging a file. Engines score
behaviour and structure, and NexDesk has several traits that score high in
combination:

- a self-extracting stub that writes an executable into `%LOCALAPPDATA%` and
  launches it (the portable build);
- an updater that downloads an executable and runs it;
- screen capture plus input injection — the same primitives a remote-access
  trojan uses;
- low download prevalence compared with the binaries it is compared against.

The durable fixes are the ones that change the shape of the artifact — shipping
the MSI as the primary download, signing every shipped binary, completing
version metadata, and not masquerading as a system process. See
[CODE-SIGNING.md](CODE-SIGNING.md). Submitting a false positive is the immediate
relief, not the cure, and it has to be repeated for each new hash.

## Procedure, per release

1. **Look the hash up first.** Both Microsoft and VirusTotal will answer for a
   file they have already seen, which saves a submission:
   - <https://www.microsoft.com/en-us/wdsi/filesubmission> → *Search file hash*
   - `https://www.virustotal.com/gui/file/<sha256>`

   If VirusTotal shows zero detections, the reporter's engine is probably
   working from stale definitions — reply with the VirusTotal link.

2. **Submit to Microsoft** using the text below. One submission per distinct
   binary: the MSI, the portable exe, and a ZIP of the payload binaries.

3. **Escalate to any vendor still flagging it on VirusTotal** (see the list).

4. **Record it** in the log at the bottom of this file.

5. **Re-check** 24–48 hours later with the hash lookup. A false-positive
   submission that is accepted disappears from the next definition update.

### Submission settings

| Field | Value |
|---|---|
| Persona | **Software developer** |
| Product | `Microsoft Defender Antivirus` (separate submission for `Microsoft Defender SmartScreen`) |
| What do you believe this file is? | **Incorrectly detected as malware/malicious** |
| Priority | **Medium** — days. Never High; that is for active malware and paged analysts. |
| Additional information | the English text below |

Upload limit is 50 MB per file. The portable exe can exceed that; send a ZIP
encrypted with the password `infected` containing the exe plus
`librustdesk.dll` and `dylib_virtual_display.dll` extracted from
`%LOCALAPPDATA%\nexdesk`.

### Ready-to-paste text

> NexDesk is a free, open-source remote desktop application for Windows,
> licensed AGPL-3.0. Complete source is at
> https://github.com/vahidkar20/deskyar and the product page is
> https://nexdesk.ir.
>
> The detection is a false positive. Relevant context:
>
> - The submitted file is our own build output, produced by our public GitHub
>   Actions workflow (.github/workflows/nexdesk-windows.yml) from the source in
>   that repository. The workflow and the source are public.
> - The portable variant is a self-extracting wrapper. It unpacks the
>   application folder to %LOCALAPPDATA%\nexdesk and starts it. That is its
>   entire function; it is not a dropper in the malware sense, and the payload
>   it contains is our own signed application.
> - The application is a remote-support tool. Screen capture and input injection
>   are its purpose, not an incidental capability. A session cannot start
>   against a machine whose owner has not granted access, the controlled side
>   shows a visible connection indicator for the session's duration, and
>   unattended access requires the device owner to set a permanent password.
> - The application is free and funded by a single advertising slot on the home
>   screen. The ad request is anonymous: no device, install or user identifier
>   is sent. See https://github.com/vahidkar20/deskyar/blob/main/PRIVACY.md.
> - Release binaries are Authenticode-signed by the SignPath Foundation, and
>   version metadata is consistent across every shipped binary.
>
> Please re-analyse and remove the detection. The SHA-256 of the submitted file
> is: <hash>

## Vendor escalation

| Vendor | Where |
|---|---|
| Microsoft (Defender, SmartScreen, Smart App Control) | <https://www.microsoft.com/en-us/wdsi/filesubmission> |
| Kaspersky | <https://opentip.kaspersky.com/> then the false-positive form |
| ESET | <https://www.eset.com/int/support/sample-submission/> |
| Avast / AVG | <https://www.avast.com/false-positive-file-form.php> |
| Bitdefender | <https://www.bitdefender.com/consumer/support/answer/29358/> |
| Sophos | <https://support.sophos.com/> → sample submission |
| Trend Micro | <https://success.trendmicro.com/> → false positive |
| McAfee | <https://www.mcafee.com/enterprise/en-us/threat-center/submit-sample.html> |

Always include: SHA-256, the download URL, the VirusTotal link, a one-line
description, and the AGPL source URL. A vendor that can see the source resolves
these far faster than one that only sees a binary.

## Log

Add a row per submission. Keep it append-only.

| Date | Version | Artifact | SHA-256 (first 16) | Vendor | Ticket | Verdict | Answered |
|---|---|---|---|---|---|---|---|
| _example_ | 1.5.11 | `NexDesk-1.5.11-x86_64.exe` | `0000000000000000` | Microsoft | `00000000-…` | accepted, FP removed | 2026-11-16 |

## CI guard

The release workflow scans the built artifacts with Defender before upload
(`MpCmdRun.exe -Scan -ScanType 3 -File <artifact> -DisableRemediation`). For a
signed release (`SIGN_ENABLED=true`) a detection fails the run, because
publishing a file that will be quarantined on arrival is worse than a failed
build. For an unsigned build it only warns, since a known false positive should
not block development. Either way, it is cheaper to catch here than in a user's
browser.
