# CELE Topnotcher OS — v3.21.8 Manual Release Gate

v3.21.8 is a **release-governance phase**, not a CELE-content or learner-analytics phase. The frozen frontend/compiler and all CELE semantics remain untouched.

The automated Windows baseline is v3.21.7 at commit `9f5529ee96c4828faa897183182c799101b699f5`, which passed on `windows-2025`.

Final Windows release status stays **NOT READY** until every gate below has direct evidence and is explicitly marked `APPROVED` in `release-gates/v3.21.8-manual-release-gate.json`.

## Native file-picker gate

Test on an unrestricted Windows 10/11 desktop using the clean public build. Confirm that selecting a valid PDF succeeds, cancelling the picker causes no data mutation or crash, invalid/non-PDF input is rejected cleanly, and the selected PDF can be rendered and passed through the native OCR path.

Minimum evidence: Windows version, app build hash, one successful picker/import/render/OCR record, one cancel-path record, and one invalid-file rejection record.

## Display and DPI gate

Check at 100%, 125%, 150%, and 200% Windows display scaling. Use at least 1280×720 and 1920×1080 effective desktop sizes when available. Confirm that onboarding, navigation, dialogs, core study pages, native document UI, and critical controls remain usable without clipped text, unreachable buttons, overlapping panes, or broken scroll regions.

Minimum evidence: screenshots or screen recording for each scaling level plus a short defect log. Any release-blocking visual defect keeps this gate pending.

## Installed-app lifecycle gate

Use the NSIS release candidate rather than a development launch. Verify clean install, first launch, close/relaunch, persistence of a test checkpoint, backup/export if exposed, clean uninstall, and reinstall. Verify expected application-data behavior rather than assuming uninstall should erase user data.

Minimum evidence: installer hash, installed version, install/relaunch/uninstall/reinstall results, and persistence observations.

## Code-signing gate

The public Windows release binary and installer must have a valid Authenticode signature from the intended publisher certificate, with a trusted timestamp. Record `Get-AuthenticodeSignature` output or equivalent evidence for both the main executable and installer.

SmartScreen reputation is not the same thing as signature validity and must not be represented as such.

Minimum evidence: signer subject, certificate thumbprint, timestamp status, file SHA-256 values, and signature status.

## Redistribution review gate

Perform the final public-package inspection. Confirm there are no bundled private/pirated reviewer PDFs, question banks, answer keys, credentials, local user data, development-only certification fixtures that should not ship, or other non-redistributable materials.

This gate is a release/legal review and is not inferred from the prior automated empty-bank or CSP tests.

Minimum evidence: reviewer identity, review date, exact package hash, and a signed-off statement identifying the reviewed package.

## Approval rule

Do not set `nativeAdapterQA` to `approved` and do not set `releaseReady` to `true` until **all five manual gates are APPROVED with evidence**.

The GitHub `CELE v3.21.8 Manual Release Gate` workflow is deliberately fail-closed and will reject missing evidence, pending gates, or inconsistent approval flags.
