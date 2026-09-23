# CELE Topnotcher OS — v3.21.16 One-Click Manual Certification Bundle

This phase packages the exact frozen unsigned RC2 together with the v3.21.15 human desktop UI certification kit.

The generated Windows bundle contains:

- the exact frozen RC2 installer;
- `RUN-ME-v32115.cmd`;
- the guided PowerShell certification script;
- the evidence template;
- the manual-certification README;
- a bundle manifest and SHA-256 inventory.

The workflow refuses an installer whose SHA-256 differs from:

`6d5b378d3c46850c6f55e1046c9880f6fe8fa6b030bc23fc2d4cacddaa5d7d3b`

The bundle is for controlled human certification only. It does not approve the native file-picker or DPI gates, does not sign the installer, and does not set `releaseReady=true`.
