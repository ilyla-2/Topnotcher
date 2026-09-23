# CELE Topnotcher OS — v3.21.13 Installed RC2 Lifecycle

This phase tests the exact frozen v3.21.12 RC2 artifact, including its corrected direct startup into the reviewed CELE v3.21.0 frontend.

Automated scope:

- exact artifact/hash verification;
- NSIS embedded EXE verification;
- silent install;
- installed EXE matches an executable embedded in the exact frozen installer;
- installed reviewed frontend launches through WebView2/Tauri and passes the native IPC certificate;
- same-version reinstall/repair;
- second installed-app launch;
- silent uninstall;
- uninstall registration/application residual checks.

Version-to-version upgrade, human file-picker interaction, DPI/visual inspection, signing, and final redistribution remain separate gates.
