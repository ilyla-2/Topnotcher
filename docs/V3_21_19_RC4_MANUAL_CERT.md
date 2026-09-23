# CELE Topnotcher OS — v3.21.19 RC4 Manual Certification

Do not use the old v3.21.16/RC2 manual bundle for release certification.

The RC2 human test discovered a real startup-chain defect: several sidebar dropdowns did not respond because CSP extraction had omitted OCR UI helpers referenced by the main startup wire function. The corrected RC4 restores the complete missing startup helper surface and keeps the v3.21.17 capture-phase interaction fallback.

Automated RC4 evidence from GitHub Actions run `35908267625`:

- real Edge startup regression: PASS;
- Practice native handler wired: PASS;
- Progress native handler wired: PASS;
- Sources & AI native handler wired: PASS;
- System native handler wired: PASS;
- all four groups opened and closed in the interaction self-test;
- page JavaScript errors: 0;
- OCR startup helper surface present;
- WebView2/Tauri IPC: PASS 13/13;
- built installer audit: PASS;
- frozen compiler unchanged.

The one-click v3.21.19 kit always reinstalls the exact RC4 even if an older RC2 with the same display version 0.3.6 is already installed.

Run `RUN-ME-v32119.cmd`, then answer the sidebar, PDF/OCR, and DPI checks based on what you actually observe.
