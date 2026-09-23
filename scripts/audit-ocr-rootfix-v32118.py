#!/usr/bin/env python3
import argparse,hashlib,json
from pathlib import Path
COMPILER_SHA="3133e9ea5259afd12dfc8f2ba7b7cc3cdc8b4e2b089ad86bad40936e504d0ef5"
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
  ap=argparse.ArgumentParser();ap.add_argument("--frontend",required=True);ap.add_argument("--patch-report",required=True);ap.add_argument("--out",required=True);a=ap.parse_args()
  root=Path(a.frontend); m=json.loads((root/"ASTRA_PAYLOAD_MANIFEST_v3_21_0.pending.json").read_text()); pub=json.loads((root/"PUBLIC_INCLUSION_MANIFEST_v3_21_0.json").read_text()); pr=json.loads(Path(a.patch_report).read_text())
  failures=[]
  if pr.get("status")!="PASS":failures.append("rootfix report not PASS")
  if m.get("frontendVersion")!="v3.21.18-ocr-startup-rootfix":failures.append("wrong frontendVersion")
  if len(m.get("files",[]))!=105:failures.append("runtime count != 105")
  if len(pub.get("files",[]))!=114:failures.append("public count != 114")
  if sha(root/"CELE_PDF_COMPILER_ENGINE_v1_6_1.js")!=COMPILER_SHA:failures.append("compiler changed")
  rows={r["path"]:r for r in m["files"]}
  for rel in ["CELE_Topnotcher_OS_v3_21_0.html","assets/js/01-ocr-ui-wire-compat-v32118.js","assets/js/53-ui-interaction-resilience-v32117.js"]:
    p=root/rel
    if not p.is_file():failures.append("missing "+rel)
    elif rows.get(rel,{}).get("sha256")!=sha(p):failures.append("hash mismatch "+rel)
  html=(root/"CELE_Topnotcher_OS_v3_21_0.html").read_text(encoding="utf-8")
  p1=html.find('src="assets/js/01-ocr-ui-wire-compat-v32118.js"');p2=html.find('src="assets/js/02-inline-script-02.js"')
  if p1<0 or p2<0 or p1>=p2:failures.append("OCR compatibility module not loaded before main script")
  js=(root/"assets/js/01-ocr-ui-wire-compat-v32118.js").read_text(encoding="utf-8")
  for s in ["function clampScanRangeV12","function nativeOcrCurrentScanPage","function nativeOcrAllScanPages","ocrPageV15"]:
    if s not in js:failures.append("missing contract "+s)
  result={"schemaVersion":1,"phase":"v3.21.18-rootfix-audit","status":"PASS" if not failures else "FAIL","runtimeFiles":len(m["files"]),"publicFiles":len(pub["files"]),"compilerSha256":sha(root/"CELE_PDF_COMPILER_ENGINE_v1_6_1.js"),"failures":failures,"releaseReady":False}
  out=Path(a.out);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,indent=2)+"\n");print(json.dumps(result,indent=2))
  if failures:raise SystemExit(1)
if __name__=="__main__":main()
