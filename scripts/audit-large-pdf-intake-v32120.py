#!/usr/bin/env python3
import argparse,hashlib,json
from pathlib import Path
COMPILER_SHA="3133e9ea5259afd12dfc8f2ba7b7cc3cdc8b4e2b089ad86bad40936e504d0ef5"
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--frontend",required=True); ap.add_argument("--patch-report",required=True); ap.add_argument("--out",required=True); a=ap.parse_args()
    root=Path(a.frontend); m=json.loads((root/"ASTRA_PAYLOAD_MANIFEST_v3_21_0.pending.json").read_text(encoding="utf-8")); pub=json.loads((root/"PUBLIC_INCLUSION_MANIFEST_v3_21_0.json").read_text(encoding="utf-8")); pr=json.loads(Path(a.patch_report).read_text(encoding="utf-8"))
    failures=[]
    if pr.get("status")!="PASS": failures.append("patch report not PASS")
    if m.get("frontendVersion")!="v3.21.20-large-pdf-intake-resilience": failures.append("wrong frontendVersion")
    if len(m.get("files",[]))!=106: failures.append("runtime count != 106")
    if len(pub.get("files",[]))!=115: failures.append("public count != 115")
    if sha(root/"CELE_PDF_COMPILER_ENGINE_v1_6_1.js")!=COMPILER_SHA: failures.append("compiler changed")
    rows={r["path"]:r for r in m["files"]}
    req=["CELE_Topnotcher_OS_v3_21_0.html","assets/js/01-ocr-ui-wire-compat-v32118.js","assets/js/53-ui-interaction-resilience-v32117.js","assets/js/54-large-pdf-intake-resilience-v32120.js"]
    for rel in req:
        p=root/rel
        if not p.is_file(): failures.append("missing "+rel)
        elif rows.get(rel,{}).get("sha256")!=sha(p): failures.append("hash mismatch "+rel)
    html=(root/"CELE_Topnotcher_OS_v3_21_0.html").read_text(encoding="utf-8")
    if html.find('src="assets/js/54-large-pdf-intake-resilience-v32120.js"')<html.find('src="assets/js/53-ui-interaction-resilience-v32117.js"'): failures.append("large PDF module load order wrong")
    js=(root/"assets/js/54-large-pdf-intake-resilience-v32120.js").read_text(encoding="utf-8")
    for s in ["LARGE_BYTES=8*1024*1024","blobToBase64Responsive","native-large","baseProcessIntakeFile","register_source_pdf","CELE_LARGE_PDF_V32120"]:
        if s not in js: failures.append("missing contract "+s)
    result={"schemaVersion":1,"phase":"v3.21.20-large-pdf-source-audit","status":"PASS" if not failures else "FAIL","runtimeFiles":len(m["files"]),"publicFiles":len(pub["files"]),"compilerSha256":sha(root/"CELE_PDF_COMPILER_ENGINE_v1_6_1.js"),"failures":failures,"releaseReady":False}
    out=Path(a.out);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8");print(json.dumps(result,indent=2))
    if failures: raise SystemExit(1)
if __name__=="__main__": main()
