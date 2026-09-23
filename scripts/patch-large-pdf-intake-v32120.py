#!/usr/bin/env python3
import argparse,copy,hashlib,json
from pathlib import Path
COMPILER_SHA="3133e9ea5259afd12dfc8f2ba7b7cc3cdc8b4e2b089ad86bad40936e504d0ef5"
HTML_REL="CELE_Topnotcher_OS_v3_21_0.html"
MANIFEST_REL="ASTRA_PAYLOAD_MANIFEST_v3_21_0.pending.json"
PUBLIC_REL="PUBLIC_INCLUSION_MANIFEST_v3_21_0.json"
JS_REL="assets/js/54-large-pdf-intake-resilience-v32120.js"
TAG='<script id="largePdfIntakeResilienceV32120" src="'+JS_REL+'"></script>'
JS=r"""(()=>{
'use strict';
const VERSION='v3.21.20';
const LARGE_BYTES=8*1024*1024;
const RAW_CHUNK=3*8192;
const YIELD_EVERY=16;
const yieldUi=()=>new Promise(resolve=>setTimeout(resolve,0));
let lastRoute='none';
function isPdf(file){return !!file&&((file.type||'').toLowerCase()==='application/pdf'||/\.pdf$/i.test(file.name||''))}
function nativeAvailable(){return !!window.__TAURI__?.core?.invoke&&!!window.CELEDocumentIO?.isNative?.()}
function shouldRouteNativeLarge(file){return isPdf(file)&&nativeAvailable()&&Number(file.size||0)>=LARGE_BYTES}
async function blobToBase64Responsive(blob,onProgress){
  const bytes=new Uint8Array(await blob.arrayBuffer()),parts=[],total=Math.max(1,Math.ceil(bytes.length/RAW_CHUNK));
  for(let i=0,part=0;i<bytes.length;i+=RAW_CHUNK,part++){
    const sub=bytes.subarray(i,Math.min(bytes.length,i+RAW_CHUNK));
    parts.push(btoa(String.fromCharCode(...sub)));
    if((part+1)%YIELD_EVERY===0){
      try{if(onProgress)onProgress(Math.min(1,(part+1)/total))}catch(e){}
      await yieldUi();
    }
  }
  try{if(onProgress)onProgress(1)}catch(e){}
  await yieldUi();
  return parts.join('');
}
const baseDocumentIO=window.CELEDocumentIO;
if(baseDocumentIO&&typeof baseDocumentIO.registerPdf==='function'){
  const baseRegisterPdf=baseDocumentIO.registerPdf.bind(baseDocumentIO);
  const registerPdfResponsive=async(blob,name)=>{
    name=name||'scan.pdf';
    if(!window.__TAURI__?.core?.invoke||Number(blob?.size||0)<LARGE_BYTES)return baseRegisterPdf(blob,name);
    const data=await blobToBase64Responsive(blob,p=>{
      try{if(typeof intakeProgress==='function')intakeProgress(Math.min(34,8+Math.round(p*24)),'Preparing large PDF for native renderer... '+Math.round(p*100)+'%')}catch(e){}
    });
    const j=await window.__TAURI__.core.invoke('register_source_pdf',{data:data,fileName:String(name)});
    if(!j?.ok||!j?.id)throw Error(j?.error||'Native PDF registration failed.');
    return{transport:'tauri-native',token:j.id,id:j.id,pageCount:+j.pageCount||0,sha256:j.id,revision:j.revision||'',preserved:!!j.preserved};
  };
  window.CELEDocumentIO=Object.freeze(Object.assign({},baseDocumentIO,{registerPdf:registerPdfResponsive}));
}
function setValue(id,value){const n=document.getElementById(id);if(n)n.value=value}
function setText(id,value){const n=document.getElementById(id);if(n)n.textContent=value}
function setHidden(id,hidden){const n=document.getElementById(id);if(n)n.classList.toggle('hidden',!!hidden)}
async function configureNativeLargePdf(file){
  intake.scanFile=file;intake.rawText='';intake.extractor='native large-PDF review/OCR';
  intake.warnings.push('Large PDF routed directly to the native Windows renderer/OCR path to keep the UI responsive; browser-side whole-file PDF parsing was skipped.');
  if(typeof refreshOcrBackendV15==='function')await refreshOcrBackendV15(false);
  if(!intake.rendererAvailable||!nativeAvailable())throw new Error('Native Windows PDF renderer is unavailable for large-PDF safe mode.');
  intakeProgress(8,'Registering '+file.name+' with the native Windows PDF adapter...');
  const ref=await window.CELEDocumentIO.registerPdf(file,file.name||'scan.pdf');
  intake.scanBridgePdfToken=ref.token;intake.scanBridgePdfTransport=ref.transport;intake.scanFingerprint=ref.sha256||ref.id||ref.token;intake.scanBridgePdfFingerprint=intake.scanFingerprint;
  intake.scanPageCount=Math.max(1,Number(ref.pageCount)||1);intake.scanObjectUrl=URL.createObjectURL(file);
  const profiles=(typeof SCAN_PROFILES!=='undefined'&&SCAN_PROFILES)||{},profile=profiles[intake.scanFingerprint]||null;intake.scanProfile=profile;
  const cat=profile?.category||(typeof inferScanCategory==='function'?inferScanCategory(file.name):'AUTO / MIXED'),count=profile?.count||null;
  setHidden('scanPanel',false);setText('scanPagesBadge',String(intake.scanPageCount)+' page'+(intake.scanPageCount===1?'':'s'));setValue('scanCategory',cat);setText('scanCategoryBadge','Category: '+(cat||'AUTO / MIXED'));setValue('scanQuestionCount',count||'');
  const pageInput=document.getElementById('scanPreviewPage'),startInput=document.getElementById('scanStartPage'),endInput=document.getElementById('scanEndPage');
  if(pageInput){pageInput.max=intake.scanPageCount;pageInput.value=1}if(startInput){startInput.max=intake.scanPageCount;startInput.value=1}
  if(endInput){endInput.max=intake.scanPageCount;endInput.value=Math.min(intake.scanPageCount,Math.max(1,profile?.pages||intake.scanPageCount))}
  intake.scanRangeStart=1;intake.scanRangeEnd=Number(endInput?.value)||intake.scanPageCount;setValue('scanPageMap',profile?.pageMap||'');setValue('scanSolutionMap',profile?.solutionParts?.[0]?.solutionMap||'');
  const golden=(typeof OCR_GOLDEN_DATA!=='undefined'&&OCR_GOLDEN_DATA)||{},hasStructured=!!(profile?.ocrKey&&golden[profile.ocrKey]);setHidden('buildStructuredSetBtn',!hasStructured);setHidden('buildGenericOcrDraftBtn',false);
  const msg=document.getElementById('scanProfileMsg');
  if(msg)msg.textContent=profile?(String(profile.name||'Known scan')+' matched by file fingerprint. Expected '+profile.count+' questions.'+(hasStructured?' Structured OCR is calibrated for this exact scan.':'')):'No known scan profile matched. No question count or page map has been assumed. OCR will populate detected numbering; review gaps before import.';
  if(typeof updateScanPreview==='function')await updateScanPreview();
  intakeProgress(100,'Large PDF ready in native mode: '+intake.scanPageCount+' page(s). '+(hasStructured?'Structured OCR import is ready.':'General OCR review is ready.'));
  return{transport:ref.transport,pageCount:intake.scanPageCount,fingerprint:intake.scanFingerprint};
}
const baseProcessIntakeFile=processIntakeFile;
processIntakeFile=async function(file){
  if(!shouldRouteNativeLarge(file)){lastRoute='legacy';return baseProcessIntakeFile(file)}
  lastRoute='native-large';resetIntake();intake.fileName=file.name;setValue('intakeSetTitle',file.name.replace(/\.(pdf|txt)$/i,''));setValue('intakeSource',file.name);intakeProgress(3,'Opening large PDF '+file.name+' in native-safe mode...');
  try{
    const out=await configureNativeLargePdf(file);intake.compilerFileV3150=file;intake.compilerV3150=null;intake.compilerTransactionV3155=null;
    if(typeof updateIntakeUI==='function')updateIntakeUI();if(typeof render==='function')render();return out;
  }catch(error){
    intake.warnings.push(error?.message||String(error));intakeProgress(100,'Large PDF intake failed safely. Nothing was imported.');if(typeof updateIntakeUI==='function')updateIntakeUI();return null;
  }
};
window.CELE_LARGE_PDF_V32120=Object.freeze({version:VERSION,thresholdBytes:LARGE_BYTES,shouldRouteNativeLarge:shouldRouteNativeLarge,encodeBase64ForTest:blob=>blobToBase64Responsive(blob),run:file=>processIntakeFile(file),status:()=>({version:VERSION,thresholdBytes:LARGE_BYTES,lastRoute:lastRoute})});
})();"""
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def update(rows,path,digest,reason=None):
    for row in rows:
        if row.get("path")==path:
            row["sha256"]=digest
            if reason is not None and "reason" in row:row["reason"]=reason
            return
    row={"path":path,"sha256":digest}
    if reason is not None:row["reason"]=reason
    rows.append(row)
def main():
    ap=argparse.ArgumentParser();ap.add_argument("--frontend",required=True);ap.add_argument("--report",required=True);a=ap.parse_args()
    root=Path(a.frontend).resolve();html=root/HTML_REL;manifest_path=root/MANIFEST_REL;public_path=root/PUBLIC_REL;compiler=root/"CELE_PDF_COMPILER_ENGINE_v1_6_1.js";js=root/JS_REL
    manifest=json.loads(manifest_path.read_text(encoding="utf-8"));public=json.loads(public_path.read_text(encoding="utf-8"));before=copy.deepcopy(manifest)
    if manifest.get("frontendVersion")!="v3.21.18-ocr-startup-rootfix":raise SystemExit("v3.21.20 must layer on v3.21.18")
    if len(manifest.get("files",[]))!=105 or len(public.get("files",[]))!=114:raise SystemExit("Unexpected v3.21.18 counts")
    if sha(compiler)!=COMPILER_SHA:raise SystemExit("Frozen compiler changed")
    if js.exists():raise SystemExit("Large-PDF module already exists")
    js.write_text(JS+"\n",encoding="utf-8")
    text=html.read_text(encoding="utf-8")
    if TAG in text:raise SystemExit("v3.21.20 tag already present")
    if "</body>" not in text:raise SystemExit("Closing body tag missing")
    text=text.replace("</body>",TAG+"\n</body>",1);html.write_text(text,encoding="utf-8")
    reason="v3.21.20 large-PDF intake responsiveness patch; ordinary-PDF parser/trust/compiler/analytics semantics unchanged."
    manifest["frontendVersion"]="v3.21.20-large-pdf-intake-resilience";update(manifest["files"],HTML_REL,sha(html),reason);update(manifest["files"],JS_REL,sha(js),reason);manifest_path.write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    public["version"]="v3.21.20-large-pdf-intake-resilience";update(public["files"],HTML_REL,sha(html));update(public["files"],JS_REL,sha(js));public_path.write_text(json.dumps(public,indent=2)+"\n",encoding="utf-8")
    old={x["path"]:x["sha256"] for x in before["files"]};new={x["path"]:x["sha256"] for x in manifest["files"]};changed=[p for p in old if old[p]!=new.get(p)];added=[p for p in new if p not in old]
    if changed!=[HTML_REL] or added!=[JS_REL]:raise SystemExit("Unexpected patch scope")
    report={"schemaVersion":1,"phase":"v3.21.20-large-pdf-intake-resilience","status":"PASS","runtimeFiles":len(manifest["files"]),"publicFiles":len(public["files"]),"changedRuntimeFiles":changed,"addedRuntimeFiles":added,"compilerSha256":sha(compiler),"htmlSha256":sha(html),"largePdfModuleSha256":sha(js),"largePdfThresholdBytes":8388608,"scope":{"questionDataChanged":False,"coverageMathChanged":False,"readinessChanged":False,"studyNextChanged":False,"learnerAnalyticsChanged":False,"engineeringCalculationsChanged":False,"nscpChanged":False,"compilerChanged":False,"trustSemanticsChanged":False}}
    out=Path(a.report);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8");print(json.dumps(report,indent=2))
if __name__=="__main__":main()
