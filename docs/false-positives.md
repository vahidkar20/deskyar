# Antivirus false positives

Windows Defender and other engines periodically flag NexDesk. This file records
what was submitted, when, and what came back — partly so a repeat detection can
be answered with the previous ticket, and partly because a documented
false-positive process is evidence of good faith if a store or signing review
asks how abuse is handled.

## Why this happens

A signature is not what stops an engine from flagging a file. Engines score
behaviour and structure, and a remote-support tool has several traits that score
high in combination:

- screen capture plus input injection — the same primitives a remote-access
  trojan uses;
- an updater that downloads an executable and runs it;
- low download prevalence compared with the binaries it is compared against.

Some of what used to make this worse has been removed rather than explained
away:

| Removed | Was | Why it mattered |
|---|---|---|
| `RuntimeBroker.exe` copy + DLL injection | The privacy-mode overlay was created by copying `C:\Windows\System32\RuntimeBroker.exe` and injecting into it with `VirtualAllocEx` / `WriteProcessMemory` / `QueueUserAPC` | Process hollowing into a copy of a system binary. The strongest signal the application carried. |
| Self-extracting stub as the only Windows artifact | A single-file exe that unpacked to `%LOCALAPPDATA%` and ran | A dropper pattern, and the reason browsers showed an uncommon-file warning. An MSI is now the primary download. |
| Permanent `SoftwareSASGeneration = 1` | Installer weakened a UAC policy for the lifetime of the install | Installers that lower security policies are a known unwanted-software pattern. |
| VBScript in `%TEMP%` run by `cscript` | Desktop shortcut creation | Writing an executable script to temp and handing it to a scripting host. |
| `%TEMP%` sweep on startup | Deleted `rustdesk-*.exe` / `.msi` older than an hour | Looked like "scans temp and deletes executables", and never matched our own files anyway. |

The remaining durable fixes are signing every shipped binary and completing
version metadata. Signing is not in place yet — see the *Code signing policy*
section of the README — so detections have to be answered one hash at a time.

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

5. **Re-check** 24–48 hours later with the hash lookup. An accepted
   false-positive submission disappears from the next definition update.

### Submission settings

| Field | Value |
|---|---|
| Persona | **Software developer** |
| Product | `Microsoft Defender Antivirus` (separate submission for `Microsoft Defender SmartScreen`) |
| What do you believe this file is? | **Incorrectly detected as malware/malicious** |
| Priority | **Medium** — days. Never High; that is for active malware and paged analysts. |
| Additional information | the English text below |

Upload limit is 50 MB per file. If the portable exe exceeds that, send a ZIP
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
> - The MSI is a standard Windows Installer package. The portable variant is a
>   self-extracting wrapper that unpacks the application folder to
>   %LOCALAPPDATA%\nexdesk and starts it; that is its entire function. It is not
>   a dropper in the malware sense, and the payload it contains is our own
>   application.
> - The application is a remote-support tool. Screen capture and input injection
>   are its purpose, not an incidental capability. A session cannot start
>   against a machine whose owner has not granted access, the controlled side
>   shows a visible connection indicator for the session's duration, and
>   unattended access requires the device owner to set a permanent password.
> - The application no longer copies or injects into any system binary. Privacy
>   mode is implemented by a separate helper binary we build from our own source
>   (libs/privacy-host), which creates an ordinary overlay window and marks it
>   excluded from capture.
> - The application is free and funded by a single advertising slot on the home
>   screen. The ad request is anonymous: no device, install or user identifier
>   is sent. See https://github.com/vahidkar20/deskyar/blob/main/PRIVACY.md.
> - Version metadata is consistent across every shipped binary: the exe, the
>   DLLs and the packer all report the same product version.
>
> Note: the binary is not Authenticode-signed at this time. That is a known
> limitation, not an indication of tampering; the SHA-256 published in the
> release notes is the integrity reference.
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
| _example_ | 1.5.11 | `NexDesk-1.5.11-x64.msi` | `0000000000000000` | Microsoft | `00000000-…` | accepted, FP removed | 2026-11-16 |

## CI guard

The Windows workflow scans the built artifacts with Defender before upload
(`MpCmdRun.exe -Scan -ScanType 3 -File <artifact> -DisableRemediation`). It
reports rather than fails: an unsigned build is expected to draw occasional
detections, and blocking development over a known false positive helps nobody.
The point is to see the detection here instead of in a user's browser.
