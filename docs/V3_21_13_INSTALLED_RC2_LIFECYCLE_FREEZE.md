# CELE Topnotcher OS — v3.21.13 Installed RC2 Lifecycle Freeze

The exact frozen v3.21.12 RC2 installer completed an installed-app lifecycle certification on `windows-2025`.

## Proven

- exact RC2 installer and standalone EXE hashes verified;
- NSIS payload extracted before installation;
- installed EXE matched the executable actually embedded in the exact installer;
- silent install returned exit code 0;
- first installed launch passed the full 13-check WebView2/Tauri IPC certificate;
- same-version reinstall/repair returned exit code 0;
- post-reinstall installed launch again passed all 13 IPC checks;
- silent uninstall returned exit code 0;
- no uninstall registry entry remained;
- installed executable was removed;
- install directory had zero residual application files.

Certification run: `35899158734`

Evidence artifact: `10768276647`

Evidence artifact digest:

`sha256:1123b21265fcd90c3d3749e67e22382585ebbd51e049dc83613f6ba24143e542`

Frozen branch:

`certified/v3.21.13-installed-rc2-lifecycle`

## Important boundary

This closes the automated core of the installed-app lifecycle gate, but does not certify human native file-picker interaction, visual/DPI behavior, a real version-to-version upgrade, Authenticode signing, or final redistribution review.

`nativeAdapterQA` remains `pending-manual-desktop-gates` and `releaseReady` remains `false`.
