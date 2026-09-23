#!/usr/bin/env python3
import argparse, copy, hashlib, json, re
from pathlib import Path

COMPILER_SHA="3133e9ea5259afd12dfc8f2ba7b7cc3cdc8b4e2b089ad86bad40936e504d0ef5"
HTML_REL="CELE_Topnotcher_OS_v3_21_0.html"
MANIFEST_REL="ASTRA_PAYLOAD_MANIFEST_v3_21_0.pending.json"
PUBLIC_REL="PUBLIC_INCLUSION_MANIFEST_v3_21_0.json"
JS_REL="assets/js/01-ocr-ui-wire-compat-v32118.js"
TARGET_SRC="assets/js/02-inline-script-02.js"
TAG='<script id="ocrUiWireCompatV32118" src="'+JS_REL+'"></script>'

JS=r"""'use strict';
/* v3.21.18: restore two OCR UI wrappers lost during CSP extraction.
   The underlying renderer/OCR/parser functions remain the existing reviewed implementation. */
async function nativeOcrCurrentScanPage(){
  const status=document.getElementById('scanOcrStatus');
  try{
    if(typeof intake==='undefined'||!intake.scanFile){
      if(status)status.textContent='Select a PDF before running OCR.';
      return null;
    }
    const pageInput=document.getElementById('scanPreviewPage');
    const max=Math.max(1,Number(intake.scanPageCount)||1);
    const page=Math.max(1,Math.min(max,Number(pageInput?.value)||1));
    if(typeof ocrPageV15!=='function')throw new Error('OCR page engine is unavailable.');
    return await ocrPageV15(page,true);
  }catch(error){
    if(status)status.textContent='OCR failed: '+String(error?.message||error);
    throw error;
  }
}

async function nativeOcrAllScanPages(){
  const status=document.getElementById('scanOcrStatus');
  try{
    if(typeof intake==='undefined'||!intake.scanFile){
      if(status)status.textContent='Select a PDF before running OCR.';
      return {};
    }
    if(typeof ocrPageV15!=='function')throw new Error('OCR page engine is unavailable.');
    let start=1,end=Math.max(1,Number(intake.scanPageCount)||1);
    if(typeof clampScanRangeV12==='function'){
      const range=clampScanRangeV12();
      if(Array.isArray(range)&&range.length>=2){
        start=Math.max(1,Number(range[0])||1);
        end=Math.max(start,Number(range[1])||start);
      }
    }
    const pages={};
    for(let page=start;page<=end;page++){
      if(status)status.textContent='OCR page '+page+' of '+end+'…';
      pages[page]=await ocrPageV15(page,page===end);
    }
    if(status)status.textContent='OCR complete for pages '+start+'–'+end+'.';
    return pages;
  }catch(error){
    if(status)status.textContent='OCR failed: '+String(error?.message||error);
    throw error;
  }
}

window.CELE_OCR_UI_WIRE_V32118={
  version:'v3.21.18',
  current:()=>nativeOcrCurrentScanPage(),
  all:()=>nativeOcrAllScanPages()
};
"""

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def update(rows,path,digest,reason=None):
    for row in rows:
        if row.get("path")==path:
            row["sha256"]=digest
            if reason is not None and "reason" in row: row["reason"]=reason
            return
    row={"path":path,"sha256":digest}
    if reason is not None: row["reason"]=reason
    rows.append(row)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--frontend",required=True)
    ap.add_argument("--report",required=True)
    args=ap.parse_args()
    root=Path(args.frontend).resolve()
    html=root/HTML_REL; manifest_path=root/MANIFEST_REL; public_path=root/PUBLIC_REL
    compiler=root/"CELE_PDF_COMPILER_ENGINE_v1_6_1.js"; js=root/JS_REL
    manifest=json.loads(manifest_path.read_text(encoding="utf-8"))
    public=json.loads(public_path.read_text(encoding="utf-8"))
    before=copy.deepcopy(manifest)

    if manifest.get("frontendVersion")!="v3.21.17-ui-interaction-resilience":
        raise SystemExit("v3.21.18 must layer on the audited v3.21.17 interaction patch")
    if len(manifest.get("files",[]))!=104 or len(public.get("files",[]))!=113:
        raise SystemExit("Unexpected v3.21.17 file counts")
    if sha(compiler)!=COMPILER_SHA: raise SystemExit("Frozen compiler changed")
    if js.exists(): raise SystemExit("OCR UI compatibility module already exists")

    js.write_text(JS+"\n",encoding="utf-8")
    text=html.read_text(encoding="utf-8")
    if TAG in text: raise SystemExit("OCR UI compatibility tag already present")
    pat=re.compile(r'(<script\b[^>]*\bsrc=["\']'+re.escape(TARGET_SRC)+r'["\'][^>]*></script>)',re.I)
    if not pat.search(text): raise SystemExit("Could not locate main extracted script tag")
    text=pat.sub(TAG+r'\n\1',text,count=1)
    html.write_text(text,encoding="utf-8")

    reason="v3.21.18 restores missing OCR UI wrappers; underlying OCR engine, compiler, CELE data and analytics unchanged."
    manifest["frontendVersion"]="v3.21.18-ocr-startup-rootfix"
    update(manifest["files"],HTML_REL,sha(html),reason)
    update(manifest["files"],JS_REL,sha(js),reason)
    manifest_path.write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")

    public["version"]="v3.21.18-ocr-startup-rootfix"
    update(public["files"],HTML_REL,sha(html))
    update(public["files"],JS_REL,sha(js))
    public_path.write_text(json.dumps(public,indent=2)+"\n",encoding="utf-8")

    old={x["path"]:x["sha256"] for x in before["files"]}
    new={x["path"]:x["sha256"] for x in manifest["files"]}
    changed=[p for p in old if old[p]!=new.get(p)]
    added=[p for p in new if p not in old]
    if changed!=[HTML_REL] or added!=[JS_REL]:
        raise SystemExit(f"Unexpected v3.21.18 runtime scope: changed={changed}, added={added}")

    report={
      "schemaVersion":1,"phase":"v3.21.18-ocr-startup-rootfix","status":"PASS",
      "runtimeFiles":len(manifest["files"]),"publicFiles":len(public["files"]),
      "changedRuntimeFiles":changed,"addedRuntimeFiles":added,
      "compilerSha256":sha(compiler),"htmlSha256":sha(html),"ocrUiWireSha256":sha(js),
      "restoredSymbols":["nativeOcrCurrentScanPage","nativeOcrAllScanPages"],
      "scope":{
        "questionDataChanged":False,"coverageMathChanged":False,"readinessChanged":False,
        "studyNextChanged":False,"learnerAnalyticsChanged":False,
        "engineeringCalculationsChanged":False,"nscpChanged":False,"compilerChanged":False
      }
    }
    out=Path(args.report).resolve();out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(report,indent=2))

if __name__=="__main__": main()
