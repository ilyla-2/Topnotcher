# CELE Topnotcher OS — v3.21.12 Public Startup Routing / RC2

RC1 proved installation/package integrity but lifecycle testing discovered that the public overlay inherited the foundation shell startup URL. The app therefore opened the diagnostic foundation page instead of the reviewed CELE frontend.

RC2 fixes only release routing. The certified base configuration remains untouched. The release overlay sets the main window URL to:

`payload/CELE_Topnotcher_OS_v3_21_0.html`

The RC2 builder must launch the public-config executable and obtain the existing v3.21.7 WebView2/Tauri IPC certificate with all 13 checks passing before the installer can be accepted.

No CELE frontend, compiler, learner analytics, engineering logic, or question data is modified.
