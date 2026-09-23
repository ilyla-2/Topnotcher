# CELE Topnotcher OS — RC5 Real Preboard Regression Retest

This kit exists because the v3.21.18 RC4 human test exposed a real release-blocking defect: importing a preboard PDF caused the Windows app to become **Not Responding** before page rendering or OCR could complete.

## What RC5 changed

v3.21.20 routes native Windows PDFs of 8 MiB or larger directly to the native PDF/OCR path instead of first running the browser-side whole-file PDF parser. Large PDF transfer to Tauri is also encoded cooperatively so the WebView event loop can continue to run.

Automated Windows evidence from GitHub Actions run **35914572661**:

- large-PDF source audit: PASS
- real Microsoft Edge 20 MiB responsiveness workload: PASS
- 10 MiB native-safe intake route: PASS
- event-loop ticks during 20 MiB encoding: 58
- event-loop ticks during native-safe intake: 31
- public WebView2/Tauri IPC: PASS 13/13
- built installer audit: PASS
- frozen CELE PDF compiler SHA-256 unchanged: `3133e9ea5259afd12dfc8f2ba7b7cc3cdc8b4e2b089ad86bad40936e504d0ef5`
- no question-bank, trust, Coverage, Readiness, Study Next, analytics, engineering calculation, or NSCP semantics were changed

## What you do

Run **RUN-ME-v32121.cmd**. It will reinstall the exact unsigned RC5, launch the app, and ask you to use the **same preboard PDF that froze RC4**.

After you arm the monitor, immediately import the preboard PDF in CELE Topnotcher OS. The script samples the Windows process for 90 seconds and records whether it exits or remains Not Responding for 5 consecutive samples.

Then verify page rendering, OCR, picker Cancel, and invalid-PDF rejection. The test creates its own harmless invalid PDF fixture.

The preboard PDF itself is **not copied into the evidence package**.

A passing result is only a candidate for review. DPI at 100/125/150/200%, code signing, final redistribution review, and public release approval remain separate gates.
