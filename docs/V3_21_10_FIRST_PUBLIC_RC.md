# CELE Topnotcher OS — v3.21.10 First Public Release Candidate

v3.21.10 produces the first public-configuration release candidate, but it is intentionally unsigned and is not approved for public distribution.

The builder:

- reconstructs the exact v3.21.7 certified source;
- verifies the frozen source/runtime audit before any release overlay;
- applies only the approved v3.21.9 release identity: publisher brand ace and bundle identifier com.ace.celetopnotcher;
- stages the exact 103-file frozen frontend into Tauri's production frontendDist;
- builds the Windows x64 application and NSIS installer;
- requires both generated binaries to be Authenticode NotSigned;
- extracts the NSIS installer with 7-Zip and scans the built payload for reviewer/source PDFs, signing-key containers, private-source directory names, private-content markers, and high-confidence credential patterns;
- records SHA-256 hashes and toolchain versions;
- uploads an RC evidence artifact for controlled manual desktop testing.

It never marks code signing, nativeAdapterQA, final redistribution review, or releaseReady as approved. No GitHub Release is created by this phase.
