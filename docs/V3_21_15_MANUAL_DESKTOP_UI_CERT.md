# CELE Topnotcher OS — v3.21.15 Manual Desktop UI Certification Kit

v3.21.15 packages the two release gates that cannot be honestly proven by the hosted CI evidence: **human native file-picker interaction** and **visual/DPI behavior**.

Run this only on an unrestricted Windows desktop using the exact frozen unsigned RC2 installer.

## Exact installer

File:

`CELE-Topnotcher-OS-v3.21.12-RC2-unsigned-setup.exe`

Required SHA-256:

`6d5b378d3c46850c6f55e1046c9880f6fe8fa6b030bc23fc2d4cacddaa5d7d3b`

The script refuses any other installer.

## Run

Open PowerShell in the repository folder and run:

`powershell -ExecutionPolicy Bypass -File .\manual-certification\run-v32115-desktop-ui-cert.ps1 -InstallerPath "C:\path\to\CELE-Topnotcher-OS-v3.21.12-RC2-unsigned-setup.exe"`

The kit will:

- verify the exact RC2 SHA-256 and expected unsigned state;
- silently install RC2 if the exact version is not already installed;
- launch the app normally, without certification injection;
- generate a deliberately invalid PDF fixture for rejection testing;
- guide the tester through valid import, render/OCR, cancel, and invalid-file behavior;
- guide the tester through 100%, 125%, 150%, and 200% display scaling;
- capture a full virtual-desktop screenshot at every requested scale;
- record measured system DPI, pass/fail answers, notes, environment metadata, and SHA-256 hashes;
- create one evidence ZIP.

## Evidence review rule

Even if every answer is positive, the script reports `COMPLETE_PASS_CANDIDATE`, not `APPROVED`.

Upload the resulting evidence ZIP for review. Only after reviewing the screenshots/report should the repository's file-picker and DPI gates be changed to `APPROVED`.

Code signing and final signed-package redistribution review remain separate gates.
