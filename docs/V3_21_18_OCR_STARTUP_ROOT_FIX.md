# v3.21.18 OCR Startup Root Fix / RC4

RC2 manual testing exposed a systemic UI failure. v3.21.17 made sidebar dropdowns resilient, but real-browser diagnostics identified the underlying startup exception: `wire()` referenced `nativeOcrCurrentScanPage` and `nativeOcrAllScanPages`, while neither wrapper existed after CSP extraction.

v3.21.18 restores only those two missing UI wrappers in a classic script loaded before `assets/js/02-inline-script-02.js`. They delegate to the existing reviewed `ocrPageV15` OCR engine and selected-page range logic.

RC4 cannot build unless a real Microsoft Edge load reports zero page errors, the original compact-navigation onclick handlers are wired, all four sidebar cluster interactions pass, and the existing resilient interaction layer also passes.

The compiler and CELE question/data/analytics/engineering semantics remain unchanged.
