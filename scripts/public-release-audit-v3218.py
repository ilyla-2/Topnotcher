#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
from pathlib import Path

FROZEN_COMPILER_SHA = "3133e9ea5259afd12dfc8f2ba7b7cc3cdc8b4e2b089ad86bad40936e504d0ef5"
FROZEN_HTML_SHA = "fc445a89a4d8bfb8130b04d1a392c7e0507444cb098deaeac53e2773494fe862"
EXPECTED_RUNTIME_FILES = 103
ALLOWED_NONRUNTIME_PDF = "foundation_0_3_6/tests/fixtures/native-cert-two-page.pdf"
EXPECTED_FIXTURE_SHA = "f2da9f346e5759428a5320d59c335f28a8cd5bf9ce44b85861a62b5743cdb927"

DENY_RUNTIME_EXT = {".pdf", ".zip", ".7z", ".rar", ".exe", ".dll", ".pfx", ".p12", ".pem", ".key", ".celebak", ".sqlite", ".db"}
DENY_RUNTIME_PARTS = {"trusted_content", "nscp_sources", "formula_sources", "formula_figures", "reviewers", "compiled_reviewers"}
DENY_REPO_SECRET_EXT = {".pfx", ".p12", ".pem", ".key"}
ACTUAL_SECRET_PATTERNS = [
    ("google_api_key", re.compile(r"AIza[0-9A-Za-z_-]{30,}")),
    ("github_pat", re.compile(r"github_pat_[A-Za-z0-9_]{25,}")),
    ("github_classic_token", re.compile(r"ghp_[A-Za-z0-9]{30,}")),
]
PRIVATE_RUNTIME_MARKERS = [
    "const OCR_PAGE_IMAGES=",
    "const TERM_QUESTIONS=",
    "const TRUSTED_V3141=",
    "const TRUSTED_V3142=",
    "const TRUSTED_V3143=",
    "-----BEGIN PRIVATE KEY-----",
    "-----BEGIN RSA PRIVATE KEY-----",
]

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    root = Path(args.root).resolve()
    out = Path(args.out).resolve()
    front = root / "frontend_v3_21_0"
    foundation = root / "foundation_0_3_6"
    failures = []

    if not front.is_dir():
        failures.append("Missing frontend_v3_21_0")
    if not foundation.is_dir():
        failures.append("Missing foundation_0_3_6")
    if failures:
        raise SystemExit("; ".join(failures))

    manifest = json.loads((front / "ASTRA_PAYLOAD_MANIFEST_v3_21_0.pending.json").read_text(encoding="utf-8"))
    rows = manifest.get("files", [])
    if len(rows) != EXPECTED_RUNTIME_FILES:
        failures.append(f"Runtime manifest count {len(rows)} != {EXPECTED_RUNTIME_FILES}")
    if manifest.get("entry") != "CELE_Topnotcher_OS_v3_21_0.html":
        failures.append("Unexpected frozen frontend entrypoint")
    if manifest.get("cspReview") != "approved":
        failures.append("CSP review is not approved")
    if manifest.get("emptyBankQA") != "approved":
        failures.append("Empty-bank QA is not approved")

    seen = set()
    runtime_bytes = 0
    for row in rows:
        rel = row.get("path", "")
        expected = row.get("sha256", "")
        p = front / rel
        if rel in seen:
            failures.append(f"Duplicate runtime manifest path: {rel}")
            continue
        seen.add(rel)
        if not p.is_file():
            failures.append(f"Missing runtime file: {rel}")
            continue
        actual = sha256(p)
        if actual != expected:
            failures.append(f"Runtime hash mismatch: {rel}")
        runtime_bytes += p.stat().st_size
        rp = Path(rel)
        if rp.suffix.lower() in DENY_RUNTIME_EXT:
            failures.append(f"Forbidden runtime extension: {rel}")
        if any(part.lower() in DENY_RUNTIME_PARTS for part in rp.parts):
            failures.append(f"Forbidden private/source runtime path: {rel}")
        if rp.suffix.lower() in {".html", ".js", ".json", ".svg"}:
            text = p.read_text(encoding="utf-8", errors="ignore")
            for marker in PRIVATE_RUNTIME_MARKERS:
                if marker in text:
                    failures.append(f"Private/secret runtime marker {marker!r} in {rel}")
            for name, pat in ACTUAL_SECRET_PATTERNS:
                if pat.search(text):
                    failures.append(f"Potential credential ({name}) in runtime file {rel}")

    compiler = front / "CELE_PDF_COMPILER_ENGINE_v1_6_1.js"
    html = front / "CELE_Topnotcher_OS_v3_21_0.html"
    if sha256(compiler) != FROZEN_COMPILER_SHA:
        failures.append("Frozen compiler SHA-256 changed")
    if sha256(html) != FROZEN_HTML_SHA:
        failures.append("Frozen frontend HTML SHA-256 changed")

    forbidden_binary_files = []
    pdfs = []
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        rel = p.relative_to(root).as_posix()
        if p.suffix.lower() == ".pdf":
            pdfs.append(rel)
        if p.suffix.lower() in DENY_REPO_SECRET_EXT:
            forbidden_binary_files.append(rel)

    if forbidden_binary_files:
        failures.append("Secret/key container files present: " + ", ".join(sorted(forbidden_binary_files)))

    unexpected_pdfs = [x for x in pdfs if x != ALLOWED_NONRUNTIME_PDF]
    if unexpected_pdfs:
        failures.append("Unexpected PDF(s) in certification/public source payload: " + ", ".join(sorted(unexpected_pdfs)))
    fixture = root / ALLOWED_NONRUNTIME_PDF
    if not fixture.is_file() or sha256(fixture) != EXPECTED_FIXTURE_SHA:
        failures.append("Synthetic native-cert PDF fixture missing or changed")

    forbidden_dirs = []
    for name in ["trusted_content", "nscp_sources", "formula_sources", "formula_figures"]:
        forbidden_dirs.extend(str(p.relative_to(root)).replace("\\", "/") for p in root.rglob(name) if p.is_dir())
    if forbidden_dirs:
        failures.append("Private/source directories physically present: " + ", ".join(sorted(forbidden_dirs)))

    metadata = json.loads((foundation / "release/metadata.json").read_text(encoding="utf-8"))
    config = json.loads((foundation / "src-tauri/tauri.conf.json").read_text(encoding="utf-8"))
    release_blockers = []
    if str(metadata.get("publisher", "")).startswith("UNSET") or not metadata.get("publisher"):
        release_blockers.append("publisher identity is unset")
    if config.get("identifier") == "local.cele.topnotcher.foundation":
        release_blockers.append("production bundle identifier is still the foundation placeholder")
    if metadata.get("signed") is not True:
        release_blockers.append("release metadata is not signed")
    if metadata.get("publicReleaseApproved") is not True:
        release_blockers.append("publicReleaseApproved is false")
    if manifest.get("redistributionReview") != "approved":
        release_blockers.append("frontend redistributionReview remains pending")
    if manifest.get("nativeAdapterQA") != "approved":
        release_blockers.append("frontend nativeAdapterQA remains pending")

    report = {
        "schemaVersion": 1,
        "phase": "v3.21.8-public-package-preaudit",
        "status": "PASS" if not failures else "FAIL",
        "scope": "reconstructed v3.21.7 certification/public source payload; not a final signed installer legal approval",
        "runtime": {
            "manifestFiles": len(rows),
            "runtimeBytes": runtime_bytes,
            "entry": manifest.get("entry"),
            "compilerSha256": sha256(compiler),
            "htmlSha256": sha256(html),
        },
        "contentBoundary": {
            "unexpectedPdfs": unexpected_pdfs,
            "allowedSyntheticFixture": ALLOWED_NONRUNTIME_PDF,
            "allowedSyntheticFixtureSha256": sha256(fixture) if fixture.is_file() else None,
            "secretContainerFiles": forbidden_binary_files,
            "physicallyPresentPrivateSourceDirs": forbidden_dirs,
            "note": "Source-family/profile names in compiler/UI are code labels only; no reviewer/source PDFs are approved by this audit."
        },
        "releaseBlockers": release_blockers,
        "failures": failures,
        "redistributionApproval": "PENDING_HUMAN_FINAL_PACKAGE_REVIEW",
        "releaseReady": False,
    }

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    if failures:
        raise SystemExit(1)

if __name__ == "__main__":
    main()
