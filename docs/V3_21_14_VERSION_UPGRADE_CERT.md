# CELE Topnotcher OS — v3.21.14 Version-to-Version Upgrade Certification

This phase tests a real Windows version transition rather than a same-version reinstall.

The test installs the exact frozen unsigned RC2 version 0.3.6, confirms its installed application passes all 13 WebView2/Tauri IPC checks, then builds an unsigned 0.3.7 upgrade installer from the same certified frontend/compiler/native baseline and the same public identifier `com.ace.celetopnotcher`.

The 0.3.7 installer is installed over 0.3.6. The workflow requires Windows uninstall registration to advance to 0.3.7, the installed executable to match the executable embedded in the 0.3.7 installer, all 13 IPC checks to pass after upgrade, and uninstall to remove the registered application/executable.

This test deliberately does not claim user-data persistence, human file-picker interaction, DPI/visual inspection, signing, or final redistribution approval.
