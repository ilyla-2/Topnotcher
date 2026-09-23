#!/usr/bin/env python3
import argparse, hashlib, json, re
from pathlib import Path

COMPILER_SHA="3133e9ea5259afd12dfc8f2ba7b7cc3cdc8b4e2b089ad86bad40936e504d0ef5"
JS_REL="assets/js/53-ui-interaction-resilience-v32117.js"
HTML_REL="CELE_Topnotcher_OS_v3_21_0.html"
PUBLIC_REL="PUBLIC_INCLUSION_MANIFEST_v3_21_0.json"
MANIFEST_REL="ASTRA_PAYLOAD_MANIFEST_v3_21_0.pending.json"
FORBIDDEN_EXT={".pdf",".zip",".7z",".rar",".pfx",".p12",".pem",".key",".celebak",".sqlite",".db"}
SECRET_PATTERNS=[
 ("google_api_key",re.compile(r"AIza[0-9A-Za-z_-]{30,}")),
 ("github_pat",re.compile(r"github_pat_[A-Za-z0-9_]{25,}")),
 ("github_classic_token",re.compile(r"ghp_[A-Za-z0-9]{30,}")),
]
PRIVATE_MARKERS=[
 "const OCR_PAGE_IMAGES=","const TERM_QUESTIONS=","const TRUSTED_V3141=",
 "const TRUSTED_V3142=","const TRUSTED_V3143=","-----BEGIN PRIVATE KEY-----",
 "-----BEGIN RSA PRIVATE KEY-----"
]

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--frontend",required=True)
    ap.add_argument("--patch-report",required=True)
    ap.add_argument("--out",required=True)
    args=ap.parse_args()
    root=Path(args.frontend).resolve()
    patch=json.loads(Path(args.patch_report).read_text(encoding="utf-8"))
    failures=[]

    manifest=json.loads((root/MANIFEST_REL).read_text(encoding="utf-8"))
    public=json.loads((root/PUBLIC_REL).read_text(encoding="utf-8"))
    rows=manifest.get("files",[])
    if patch.get("status")!="PASS": failures.append("Patch report is not PASS")
    if manifest.get("frontendVersion")!="v3.21.17-ui-interaction-resilience": failures.append("Wrong frontendVersion")
    if len(rows)!=104: failures.append(f"Runtime file count {len(rows)} != 104")
    if len(public.get("files",[]))!=113: failures.append(f"Public file count {len(public.get('files',[]))} != 113")
    if manifest.get("entry")!=HTML_REL: failures.append("Entry path changed")
    if manifest.get("cspReview")!="approved": failures.append("CSP review regressed")
    if manifest.get("emptyBankQA")!="approved": failures.append("Empty-bank QA regressed")
    if sha(root/"CELE_PDF_COMPILER_ENGINE_v1_6_1.js")!=COMPILER_SHA: failures.append("Frozen compiler changed")

    seen=set()
    for row in rows:
        rel=row.get("path","")
        if rel in seen: failures.append(f"Duplicate manifest path {rel}")
        seen.add(rel)
        p=root/rel
        if not p.is_file():
            failures.append(f"Missing runtime file {rel}")
            continue
        if sha(p)!=row.get("sha256"): failures.append(f"Manifest hash mismatch {rel}")
        if p.suffix.lower() in FORBIDDEN_EXT: failures.append(f"Forbidden runtime extension {rel}")

    js=root/JS_REL
    html=root/HTML_REL
    if not js.is_file(): failures.append("Interaction resilience module missing")
    tag='src="assets/js/53-ui-interaction-resilience-v32117.js"'
    if html.read_text(encoding="utf-8").count(tag)!=1: failures.append("Interaction module script tag missing or duplicated")
    js_text=js.read_text(encoding="utf-8") if js.is_file() else ""
    for required in [
        "document.addEventListener('click',captureClick,true)",
        "[data-cluster-toggle]",
        "focusToolsBtnV171",
        "selfTest",
        "stopImmediatePropagation"
    ]:
        if required not in js_text: failures.append(f"Interaction module missing required contract: {required}")

    secret_hits=[]
    marker_hits=[]
    for row in rows:
        p=root/row.get("path","")
        if not p.is_file() or p.suffix.lower() not in {".html",".js",".json",".svg"} or p.stat().st_size>8*1024*1024:
            continue
        text=p.read_text(encoding="utf-8",errors="ignore")
        for marker in PRIVATE_MARKERS:
            if marker in text: marker_hits.append({"path":row["path"],"marker":marker})
        for name,pat in SECRET_PATTERNS:
            if pat.search(text): secret_hits.append({"path":row["path"],"kind":name})
    if marker_hits: failures.append("Private-content marker found")
    if secret_hits: failures.append("Credential-like pattern found")

    result={
      "schemaVersion":1,
      "phase":"v3.21.17-ui-interaction-audit",
      "status":"PASS" if not failures else "FAIL",
      "runtimeFiles":len(rows),
      "publicFiles":len(public.get("files",[])),
      "compilerSha256":sha(root/"CELE_PDF_COMPILER_ENGINE_v1_6_1.js"),
      "htmlSha256":sha(html),
      "interactionScriptSha256":sha(js) if js.is_file() else None,
      "patchScope":patch.get("scope"),
      "privateMarkerHits":marker_hits,
      "secretPatternHits":secret_hits,
      "failures":failures,
      "releaseReady":False
    }
    out=Path(args.out).resolve(); out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(result,indent=2))
    if failures: raise SystemExit(1)

if __name__=="__main__":
    main()
