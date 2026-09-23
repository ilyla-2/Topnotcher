#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
from pathlib import Path

FORBIDDEN_EXTENSIONS = {".pdf", ".zip", ".7z", ".rar", ".pfx", ".p12", ".pem", ".key", ".celebak", ".sqlite", ".db"}
FORBIDDEN_PATH_TOKENS = {
    "trusted_content", "nscp_sources", "formula_sources", "formula_figures",
    "compiled_reviewers", "reviewers", "answer_keys", "private_reviewers"
}
TEXT_EXTENSIONS = {".html", ".js", ".json", ".css", ".txt", ".md", ".toml", ".yml", ".yaml", ".xml", ".ini", ".cfg"}
PRIVATE_MARKERS = [
    "const OCR_PAGE_IMAGES=",
    "const TERM_QUESTIONS=",
    "const TRUSTED_V3141=",
    "const TRUSTED_V3142=",
    "const TRUSTED_V3143=",
    "-----BEGIN PRIVATE KEY-----",
    "-----BEGIN RSA PRIVATE KEY-----",
]
SECRET_PATTERNS = [
    ("google_api_key", re.compile(r"AIza[0-9A-Za-z_-]{30,}")),
    ("github_pat", re.compile(r"github_pat_[A-Za-z0-9_]{25,}")),
    ("github_classic_token", re.compile(r"ghp_[A-Za-z0-9]{30,}")),
]

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--extracted", required=True)
    ap.add_argument("--installer", required=True)
    ap.add_argument("--executable", required=True)
    ap.add_argument("--source-audit", required=True)
    ap.add_argument("--identity-report", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    extracted = Path(args.extracted).resolve()
    installer = Path(args.installer).resolve()
    executable = Path(args.executable).resolve()
    source_audit = Path(args.source_audit).resolve()
    identity_report = Path(args.identity_report).resolve()
    out = Path(args.out).resolve()

    failures = []
    warnings = []

    for p in [installer, executable, source_audit, identity_report]:
        if not p.is_file():
            failures.append(f"Missing required RC evidence/input: {p}")

    source = json.loads(source_audit.read_text(encoding="utf-8"))
    identity = json.loads(identity_report.read_text(encoding="utf-8"))
    if source.get("status") != "PASS":
        failures.append("Source/runtime redistribution pre-audit is not PASS")
    after = identity.get("after", {})
    if after.get("identifier") != "com.ace.celetopnotcher":
        failures.append("Release identity overlay identifier mismatch")
    if after.get("publisher") != "ace":
        failures.append("Release identity overlay publisher mismatch")
    if after.get("signed") is not False or after.get("publicReleaseApproved") is not False:
        failures.append("Release identity overlay improperly claims signed/public approval")
    if identity.get("frontendTouched") is not False or identity.get("compilerTouched") is not False:
        failures.append("Release identity overlay reports frontend/compiler mutation")

    forbidden_files = []
    forbidden_paths = []
    text_marker_hits = []
    secret_hits = []
    extracted_files = 0
    extracted_bytes = 0

    for p in extracted.rglob("*"):
        if not p.is_file():
            continue
        extracted_files += 1
        extracted_bytes += p.stat().st_size
        rel = p.relative_to(extracted).as_posix()
        parts = {part.lower() for part in p.relative_to(extracted).parts}
        if p.suffix.lower() in FORBIDDEN_EXTENSIONS:
            forbidden_files.append(rel)
        if parts & FORBIDDEN_PATH_TOKENS:
            forbidden_paths.append(rel)

        if p.suffix.lower() in TEXT_EXTENSIONS and p.stat().st_size <= 8 * 1024 * 1024:
            text = p.read_text(encoding="utf-8", errors="ignore")
            for marker in PRIVATE_MARKERS:
                if marker in text:
                    text_marker_hits.append({"path": rel, "marker": marker})
            for name, pattern in SECRET_PATTERNS:
                if pattern.search(text):
                    secret_hits.append({"path": rel, "kind": name})

    if forbidden_files:
        failures.append("Forbidden redistributable file types found in installer extraction")
    if forbidden_paths:
        failures.append("Private/source directory names found in installer extraction")
    if text_marker_hits:
        failures.append("Private-content markers found in installer extraction")
    if secret_hits:
        failures.append("Potential credentials found in installer extraction")

    report = {
        "schemaVersion": 1,
        "phase": "v3.21.10-built-windows-rc-audit",
        "status": "PASS" if not failures else "FAIL",
        "releaseType": "UNSIGNED_RELEASE_CANDIDATE_NOT_FOR_PUBLIC_DISTRIBUTION",
        "product": "CELE Topnotcher OS",
        "publisherBrand": "ace",
        "identifier": "com.ace.celetopnotcher",
        "installer": {
            "name": installer.name,
            "bytes": installer.stat().st_size if installer.is_file() else None,
            "sha256": sha256(installer) if installer.is_file() else None,
        },
        "executable": {
            "name": executable.name,
            "bytes": executable.stat().st_size if executable.is_file() else None,
            "sha256": sha256(executable) if executable.is_file() else None,
        },
        "installerExtraction": {
            "files": extracted_files,
            "bytes": extracted_bytes,
            "forbiddenFiles": sorted(forbidden_files),
            "forbiddenPaths": sorted(forbidden_paths),
            "privateMarkerHits": text_marker_hits,
            "secretPatternHits": secret_hits,
        },
        "sourceAuditStatus": source.get("status"),
        "identityOverlayStatus": identity.get("after"),
        "warnings": warnings,
        "failures": failures,
        "codeSigning": "NOT_CONFIGURED",
        "nativeAdapterQA": "pending-manual-desktop-gates",
        "finalRedistributionReview": "PENDING",
        "releaseReady": False,
    }

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    if failures:
        raise SystemExit(1)

if __name__ == "__main__":
    main()
