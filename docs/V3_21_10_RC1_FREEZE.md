# CELE Topnotcher OS — v3.21.10 RC1 Freeze

The first Windows release candidate built and audited successfully on GitHub Actions.

- RC branch: `rc/v3.21.10-windows-rc1-unsigned`
- RC source commit: `0bd13eee4c2ffb847ab1c3512bc91ea3f9108cfd`
- Actions run: `35894857839` (#4)
- Runner: `windows-2025`
- Result: **PASS**
- Artifact ID: `10767226392`
- Artifact digest: `sha256:99b6f92c75e8cf09fca18e14a73b32f9d31242aec68d7290f9229eb0ae0667d8`

## Binaries

Application EXE:

`CELE-Topnotcher-OS-v3.21.10-RC1-unsigned.exe`

SHA-256:

`baeaeddd1175100741d0c3c6bd1f34454399a4a8636312d9127af44d71faef77`

NSIS installer:

`CELE-Topnotcher-OS-v3.21.10-RC1-unsigned-setup.exe`

SHA-256:

`940c0e68c2097080c8e1e1c2da02d3aca7c018e08214911ad24bf718cadeb753`

Internal RC archive SHA-256:

`05d0b2df747804bf06bb39cbbc4669dfae1802dd2deb9e93c26cbe9099338736`

## Audit result

The built NSIS payload audit passed:

- 8 extracted files;
- zero forbidden file types;
- zero private/source directory hits;
- zero private-content marker hits;
- zero credential-pattern hits;
- source/runtime audit PASS;
- publisher brand `ace`;
- public identifier `com.ace.celetopnotcher`;
- certified base identifier remained `local.cele.topnotcher.foundation`.

## Release boundary

This is an **unsigned controlled-test release candidate**, not a public release.

Authenticode is deliberately `NotSigned`. Manual file-picker, DPI/display, installed-app lifecycle, code-signing, and final redistribution gates remain pending. `releaseReady` remains `false`.
