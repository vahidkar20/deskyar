# Code signing policy

**Free code signing provided by [SignPath.io](https://signpath.io), certificate
by [SignPath Foundation](https://signpath.org).**

NexDesk's Windows release artifacts are Authenticode-signed, with an RFC 3161
timestamp, before they are published. The certificate is issued to the SignPath
Foundation — that is the publisher name Windows shows — because certificate
authorities do not issue code-signing certificates to open-source projects in
the project's own name.

## Team and roles

Signing is a human-approved action, not an automatic consequence of a build.

| Role | Who | Responsibility |
|---|---|---|
| Author | [@vahidkar20](https://github.com/vahidkar20) | May modify source without additional review. |
| Reviewer | _to be assigned_ | Every change from a non-committer is reviewed by a team member before merge. |
| Approver | [@vahidkar20](https://github.com/vahidkar20) | Approves each signing request. A build cannot be signed without this approval. |

Multi-factor authentication is required for every team member on both GitHub and
SignPath. Until a second maintainer is added, the Author and Approver roles are
held by the same person; the two-person rule applies as soon as one exists.

## What gets signed

| Artifact | Signed | Notes |
|---|---|---|
| `NexDesk-<version>-x64.msi` | yes | primary installer |
| `NexDesk-<version>-x86_64.exe` | yes | single-file portable packer |
| `NexDesk.exe` (inside the payload) | yes | Flutter shell |
| `librustdesk.dll` (inside the payload) | yes | Rust core |
| `dylib_virtual_display.dll` (inside the payload) | yes | virtual display driver |
| `flutter_windows.dll` | no | RustDesk's patched Flutter engine, third-party (BSD) |
| `usbmmidd_v2` driver bundle | no | third-party, fetched from its own release |
| MSI `CustomActions` DLL | no | compiled into the MSI's Binary table and cannot be signed separately; the MSI that contains it is signed |

Unsigned third-party binaries are included as-is; they are not repackaged or
re-signed, because a signature on a binary we did not build would be a false
attestation.

## Build → sign → pack ordering

The portable executable embeds a brotli-compressed archive of the whole
application folder in `data.bin`. Signing only the outer stub would leave
`NexDesk.exe` and `librustdesk.dll` unsigned *inside* it, and Windows evaluates
those when the packer extracts and launches them — so the order is not
interchangeable:

```
1. build        python build.py --portable --flutter --skip-portable-pack
2. sign inner   NexDesk.exe, librustdesk.dll, dylib_virtual_display.dll
3. pack         libs/portable/generate.py  -> rustdesk-portable-packer.exe
4. build MSI    res/msi/preprocess.py + msbuild
5. sign outer   the packer exe and the MSI
6. verify       signtool verify /pa /all /v on every artifact
```

Steps 2 and 5 are separate signing requests, each requiring an Approver. A
release therefore consumes two approvals; this is inherent to signing a
self-extracting container whose payload is not a format SignPath can traverse.

The workflow is [`.github/workflows/nexdesk-windows.yml`](../.github/workflows/nexdesk-windows.yml).
Signing is gated behind the `SIGN_ENABLED` repository variable so that a
contributor's build can still run without access to the signing project; a build
with `SIGN_ENABLED` unset prints `::warning::shipping an UNSIGNED build` and
cannot be published as a release.

## Verifying a download

Windows shows the publisher on the file's **Properties → Digital Signatures**
tab. From a shell:

```powershell
Get-AuthenticodeSignature .\NexDesk-1.5.11-x64.msi |
  Format-List Status, SignerCertificate, TimeStamperCertificate

# full chain and timestamp
signtool verify /pa /all /v .\NexDesk-1.5.11-x64.msi
```

`Status` must be `Valid` and `SignerCertificate.Subject` must contain
`SignPath Foundation`. A non-null `TimeStamperCertificate` means the signature
stays valid after the certificate expires.

The same check applies to the binaries the portable build extracts:

```powershell
Get-ChildItem "$env:LOCALAPPDATA\nexdesk\*.exe","$env:LOCALAPPDATA\nexdesk\*.dll" |
  ForEach-Object { "$($_.Name): $((Get-AuthenticodeSignature $_).Status)" }
```

`flutter_windows.dll` is expected to be `NotSigned`; everything else must be
`Valid`.

## What a signature does and does not guarantee

A valid signature attests that the binary was built from this repository and
approved by the team — it is a statement about provenance, not about behaviour.
It is also not a malware verdict: SmartScreen reputation accrues separately, from
download prevalence against the certificate's thumbprint, so a freshly signed
release can still prompt for a while. Reputation also resets when the certificate
is renewed.

Antivirus false positives are handled separately; see
[false-positives.md](false-positives.md).

## Key and certificate handling

The signing key is generated and held in SignPath's HSM and never exists on a
build machine or in this repository. No private key material, password or API
token is committed here; the workflow reads `SIGNPATH_API_TOKEN` from repository
secrets.

Certificate renewal is a planned event: renewal resets SmartScreen reputation, so
the certificate is renewed with the same publisher identity and the change is
announced in the release notes.

## Changes to this policy

Any change to who may approve a signing request, or to what is signed, is made in
this file in the same pull request that changes the workflow, and is announced in
the release notes.
