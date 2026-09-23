# CELE Topnotcher OS — Windows Signing & Public Release Preparation

This phase prepares signing and release verification without pretending a certificate or final legal approval exists.

## Current release blockers

The certified v3.21.7 runtime is technically validated, but the production metadata still has:

- publisher: `UNSET — release owner must supply verified identity`
- identifier: `local.cele.topnotcher.foundation`
- signed: `false`
- publicReleaseApproved: `false`

Do not change the production identifier casually. On desktop platforms the bundle identifier is part of application identity and can affect install/update behavior and user-data locations. Choose the final identifier once, document any migration requirement, then keep it stable.

## Signing requirements

For Windows Authenticode releases:

- use SHA-256 for the file digest;
- use an RFC 3161 timestamp with SHA-256;
- sign both the application executable and the installer;
- verify the signatures after signing;
- keep signing private keys and certificate credentials outside the repository.

Do not equate a valid signature with Microsoft SmartScreen reputation. A newly signed application can still receive a SmartScreen warning while reputation develops.

## Supported signing paths

### Provider / hardware-backed certificate

If the certificate authority supplies a hardware token, cloud HSM, or vendor signing client, follow the issuer's current instructions. For modern OV/EV code-signing certificates, do not assume an exportable PFX is available.

Configure Tauri only after the final certificate/signing mechanism is known. Prefer a custom sign command when the provider requires its own client.

### Azure Artifact Signing

Tauri v2 documents Azure Artifact Signing as a supported CI-oriented path. If the release owner is eligible and chooses it, configure Azure credentials as GitHub Actions secrets and use Tauri's `bundle.windows.signCommand`.

No Azure credential, signing certificate, PFX, password, client secret, or token belongs in this repository.

## Final verification

After signing, run:

`manual-certification/verify-windows-release-signatures.ps1`

against the exact EXE and NSIS installer intended for release. The verifier requires a valid Authenticode signature, signer certificate, timestamp certificate, optional publisher-subject matching, SHA-256 evidence, and SignTool verification when SignTool is available.

The resulting JSON becomes evidence for the v3.21.8 `codeSigning` gate.

## Public package audit

The CI workflow `CELE v3.21.8 Public Package Audit` reconstructs the frozen v3.21.7 source payload and checks all 103 runtime hashes, frozen compiler/HTML hashes, absence of reviewer/source PDFs from runtime, absence of private source directories and signing-key containers, and high-confidence credential patterns.

Passing this audit is not final redistribution approval. The final signed installer must still be inspected and approved under the manual redistribution gate.

## Official references

- Microsoft SignTool: https://learn.microsoft.com/windows/win32/seccrypto/signtool
- Microsoft Authenticode timestamping: https://learn.microsoft.com/windows/win32/seccrypto/time-stamping-authenticode-signatures
- Tauri v2 Windows code signing: https://v2.tauri.app/distribute/sign/windows/
