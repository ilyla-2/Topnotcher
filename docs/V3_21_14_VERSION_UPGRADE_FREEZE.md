# CELE Topnotcher OS — v3.21.14 Version Upgrade Freeze

The exact unsigned RC2 version 0.3.6 was installed on `windows-2025`, then upgraded in place to a certification-only version 0.3.7 built from the same certified frontend/compiler/native baseline and the same public identifier.

## Proven

- RC2 0.3.6 installed and launched successfully;
- pre-upgrade installed app passed all 13 WebView2/Tauri IPC checks;
- Windows installer registration advanced from 0.3.6 to 0.3.7;
- the upgraded installed EXE matched the executable embedded in the exact 0.3.7 certification installer;
- the native data root contained 6 files before upgrade;
- the native data tree was byte-for-byte unchanged by the installer upgrade before the upgraded app launched;
- the upgraded app passed all 13 WebView2/Tauri IPC checks;
- uninstall removed the registration, executable, and install-directory application files.

Certification run: `35899772106`

Evidence artifact: `10768882584`

Evidence digest:

`sha256:24be9540e8d5b130297809e2947f29a6fd96ae294803d276aa1131e1bd9178f8`

Frozen branch:

`certified/v3.21.14-version-upgrade`

The 0.3.7 installer is certification-only and is not a public release.

Remaining release gates are human native file-picker interaction, DPI/visual inspection, code signing, and final redistribution approval. `releaseReady` remains `false`.
