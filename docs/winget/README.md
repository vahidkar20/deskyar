# winget manifests

Templates for publishing NexDesk to the Windows Package Manager community
repository (`microsoft/winget-pkgs`).

winget is worth the effort for two reasons beyond distribution: a manifest is
validated against the actual installer on every update, and a package that has
been through review counts as a prevalence and trust signal — the same thing
SmartScreen and a code-signing review look at when deciding whether a publisher
is established.

## Why this is not automated yet

The manifest must describe the **signed** MSI, with the hash of the signed bytes.
Publishing is therefore a manual step after a release is signed, not a CI job.
Automate it once the release cadence settles; until then the manual step keeps a
wrong hash out of the repository.

## Publishing a version

1. Download the signed MSI from the release and compute its hash:

   ```powershell
   Get-FileHash .\NexDesk-<version>-x64.msi -Algorithm SHA256
   ```

2. Copy the three templates into a folder named
   `manifests/n/NexDesk/NexDesk/<version>/`, replacing `<version>` and
   `<sha256>` in each file. The hash goes in lowercase hexadecimal.

3. Validate, then submit:

   ```powershell
   winget validate --manifest .\manifests\n\NexDesk\NexDesk\<version>
   winget install --manifest .\manifests\n\NexDesk\NexDesk\<version>
   ```

   Then open a pull request against `microsoft/winget-pkgs` with that folder.

## Notes

- `InstallerType: wix` is correct for an MSI built with WiX; winget uses it to
  pass the right silent-install switches. Do not change it to `exe`.
- `PackageIdentifier` is immutable once accepted. It is `NexDesk.NexDesk` and
  must stay that way across versions, even if the display name changes.
- The `InstallerUrl` must be a stable, versioned URL on `nexdesk.ir`. Do not
  point it at a `latest` path: winget verifies the hash, and a URL that silently
  starts serving a newer file breaks every existing manifest.
- Keep the `Moniker` as `nexdesk` so `winget install nexdesk` works.
