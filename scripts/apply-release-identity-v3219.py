#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

OLD_IDENTIFIER = "local.cele.topnotcher.foundation"
NEW_IDENTIFIER = "com.ace.celetopnotcher"
PUBLISHER_BRAND = "ace"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--foundation", required=True, help="Path to reconstructed foundation_0_3_6")
    ap.add_argument("--report", required=True)
    args = ap.parse_args()

    root = Path(args.foundation).resolve()
    tauri_path = root / "src-tauri" / "tauri.conf.json"
    metadata_path = root / "release" / "metadata.json"

    if not tauri_path.is_file() or not metadata_path.is_file():
        raise SystemExit("Expected foundation_0_3_6 Tauri/release metadata files were not found.")

    tauri = json.loads(tauri_path.read_text(encoding="utf-8"))
    meta = json.loads(metadata_path.read_text(encoding="utf-8"))

    current = tauri.get("identifier")
    if current != OLD_IDENTIFIER:
        raise SystemExit(f"Refusing release identity overlay: expected {OLD_IDENTIFIER!r}, found {current!r}")

    if meta.get("signed") is True:
        raise SystemExit("Refusing identity overlay on metadata already marked signed.")
    if meta.get("publicReleaseApproved") is True:
        raise SystemExit("Refusing identity overlay on metadata already marked public-release approved.")

    before = {
        "identifier": current,
        "publisher": meta.get("publisher"),
        "signed": meta.get("signed"),
        "publicReleaseApproved": meta.get("publicReleaseApproved"),
    }

    tauri["identifier"] = NEW_IDENTIFIER
    meta["publisher"] = PUBLISHER_BRAND
    meta["signed"] = False
    meta["publicReleaseApproved"] = False
    meta["releaseIdentityPhase"] = "v3.21.9"
    meta["signingStatus"] = "not-configured"

    tauri_path.write_text(json.dumps(tauri, indent=2) + "\n", encoding="utf-8")
    metadata_path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")

    report = {
        "schemaVersion": 1,
        "phase": "v3.21.9-release-identity-overlay",
        "foundation": str(root),
        "before": before,
        "after": {
            "identifier": NEW_IDENTIFIER,
            "publisher": PUBLISHER_BRAND,
            "signed": False,
            "publicReleaseApproved": False,
            "signingStatus": "not-configured",
        },
        "touchedFiles": [
            "src-tauri/tauri.conf.json",
            "release/metadata.json"
        ],
        "frontendTouched": False,
        "compilerTouched": False,
        "releaseReady": False
    }

    out = Path(args.report).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))

if __name__ == "__main__":
    main()
