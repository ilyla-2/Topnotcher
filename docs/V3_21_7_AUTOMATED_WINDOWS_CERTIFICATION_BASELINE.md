# CELE Topnotcher OS — v3.21.7 Automated Windows Certification Baseline

This document freezes the successful automated Windows certification baseline. It does **not** claim final public-release approval.

## Frozen automated baseline

- Baseline phase: **v3.21.7 — Automated WebView2/Tauri IPC Certification**
- Certified branch: `certified/v3.21.7-windows-2025`
- Certified commit: `9f5529ee96c4828faa897183182c799101b699f5`
- GitHub Actions run: **35888521612**
- Runner: **windows-2025**
- Run conclusion: **success**
- Evidence artifact ID: **10764328348**
- Evidence artifact digest: `sha256:bb9832fbeafe895c7fe439e65511b59dfec78a3b5408e2e31ab2189979a07002`
- Frozen compiler SHA-256: `3133e9ea5259afd12dfc8f2ba7b7cc3cdc8b4e2b089ad86bad40936e504d0ef5`

## Automated gates proven by the Windows 2025 run

The run established the following on a real GitHub-hosted Windows environment:

- portable/static regression suite passed;
- Rust/MSVC compilation passed;
- Windows.Data.Pdf native PDF handling passed;
- Windows.Media.Ocr text and geometry checks passed;
- native generation/revision/SHA/backup behavior passed;
- the Tauri release executable compiled and linked;
- the exact frozen v3.21.0 frontend loaded in WebView2;
- frontend JavaScript crossed the real Tauri IPC boundary into Rust successfully;
- the isolated NSIS certification installer was built successfully.

The run log ended with:

`CLOUD WINDOWS GATE: PASS`

and explicitly reported that native primitives, the frozen frontend WebView2/Tauri IPC path, and Windows build artifacts passed.

## What is intentionally not certified here

`nativeAdapterQA` remains pending manual desktop gates. Automated cloud evidence does not establish:

- native file-picker interaction under a normal user desktop;
- visual/DPI behavior across supported Windows scaling levels;
- installed application install/relaunch/update/uninstall behavior;
- Authenticode code signing and timestamp validation;
- final redistribution/legal review of the public package.

Those are controlled by the v3.21.8 manual release gate.
