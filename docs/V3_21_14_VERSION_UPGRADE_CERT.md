# CELE Topnotcher OS — v3.21.14 Version-to-Version Upgrade Certification

This certification installs exact frozen RC2 version 0.3.6, launches it through the real reviewed frontend/native IPC path to create native state, then installs a certification-only 0.3.7 package with the same public identifier.

Before launching the upgraded app, the workflow requires the entire native Topnotcher Data file tree to remain byte-for-byte unchanged. It then launches 0.3.7 and requires the 13-check IPC certificate, followed by a clean uninstall.

The 0.3.7 package is a certification fixture only and is never a public release candidate.
