# False-positive submission package

Ready-to-send text for Microsoft Defender Security Intelligence. Behavioural
verdicts (`!ml`) are corrected through these submissions, not through code
changes, so this is the step that actually stops an install from being
quarantined on a user's machine.

Replace the hashes below with the ones from the release being reported — they
change with every build, and a submission for a hash Microsoft has not seen is
answered faster.

## Where

| Field | Value |
|---|---|
| Portal | <https://www.microsoft.com/en-us/wdsi/filesubmission> |
| Persona | Software developer |
| Product | Microsoft Defender Antivirus (repeat for SmartScreen if needed) |
| Submission type | Incorrectly detected as malware/malicious |
| Priority | Medium |
| Files | the `.msi`, the portable `.exe`, and a ZIP of the installed payload |

Upload limit is 50 MB per file. If the portable exe exceeds it, send a ZIP
encrypted with the password `infected`.

## Text

> NexDesk is a free, open-source remote desktop application for Windows,
> licensed AGPL-3.0. Complete source: https://github.com/vahidkar20/deskyar
> Product page: https://nexdesk.ir
>
> Detection: `Behavior:Win32/Persistence.A!ml`
> Artifact: `NexDesk-1.5.11-x64.msi`
> SHA-256: `5f48b760e0501ddbc0d1697ac01bf0da0d11efd3f4bc45f2b2d2002d1d4ae4ed`
>
> The behaviour the model observed is the intended installation:
>
> - The package registers a Windows service (`NexDesk`) so the device can accept
>   remote connections after a reboot. That is the product; without it there is
>   no unattended access.
> - It writes the uninstall entry that Windows requires in order to list the
>   application under Apps & features.
> - It creates the Start Menu and Desktop shortcuts the user selected during
>   installation.
>
> This is the same shape as TeamViewer, AnyDesk, Splashtop and Microsoft's own
> Quick Assist. The application is not installing itself covertly: it is an
> installer doing what the user asked for, with a visible uninstaller and a
> visible entry in Apps & features.
>
> Changes already made to remove the genuinely suspicious behaviour:
>
> - No longer copies `C:\Windows\System32\RuntimeBroker.exe` and injects a DLL
>   into the copy. The privacy-mode overlay is now an ordinary helper process
>   built from our own source.
> - No longer writes a batch or cmd script to disk and runs it elevated. The
>   privileged step now runs inside the application's own elevated process and
>   receives its commands over a named pipe.
> - No longer writes a permanent `SoftwareSASGeneration` policy.
> - No longer creates a Startup-folder autorun entry.
> - No longer scans and deletes files in `%TEMP%`.
>
> Safety properties a user can verify:
>
> - A session cannot start against a machine whose owner has not granted access.
> - The controlled side shows a visible indicator for the whole session.
> - Unattended access requires the device owner to set a permanent password.
> - The uninstaller removes the service, the registry entries and the shortcuts.
>
> Please re-analyse and remove the detection. The binary is not Authenticode
> signed at this time — that is a known limitation, not an indication of
> tampering; the SHA-256 published in the release notes is the integrity
> reference.

## Per-vendor escalation

If a third-party engine also flags it, use the addresses in
[false-positives.md](false-positives.md).

## Log

Keep this append-only, one row per submission.

| Date | Version | Artifact | SHA-256 (first 16) | Vendor | Ticket | Verdict |
|---|---|---|---|---|---|---|
| _example_ | 1.5.11 | `NexDesk-1.5.11-x64.msi` | `5f48b760e0501ddb` | Microsoft | — | pending |
