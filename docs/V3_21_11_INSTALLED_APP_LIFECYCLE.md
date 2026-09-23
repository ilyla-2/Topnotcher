# CELE Topnotcher OS — v3.21.11 Installed-App Lifecycle Certification

This phase tests the exact frozen v3.21.10 RC1 artifact rather than rebuilding it.

The Windows hosted runner downloads RC1 artifact ID 10767226392 from successful run 35894857839, verifies the frozen installer and executable hashes, silently installs the NSIS package, resolves the installed application, launches the installed executable through the existing WebView2/Tauri IPC certification harness, performs a same-version reinstall/repair, launches again, silently uninstalls, and verifies the uninstall registration and application files are removed.

This does not claim a version-to-version upgrade test, human file-picker interaction, DPI/visual correctness, code signing, or final redistribution approval. Those remain separate gates.
