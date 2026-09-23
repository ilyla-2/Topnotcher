#!/usr/bin/env python3
import argparse
import copy
import hashlib
import json
from pathlib import Path

BASE_HTML_SHA = "fc445a89a4d8bfb8130b04d1a392c7e0507444cb098deaeac53e2773494fe862"
COMPILER_SHA = "3133e9ea5259afd12dfc8f2ba7b7cc3cdc8b4e2b089ad86bad40936e504d0ef5"
JS_REL = "assets/js/53-ui-interaction-resilience-v32117.js"
HTML_REL = "CELE_Topnotcher_OS_v3_21_0.html"
PUBLIC_REL = "PUBLIC_INCLUSION_MANIFEST_v3_21_0.json"
MANIFEST_REL = "ASTRA_PAYLOAD_MANIFEST_v3_21_0.pending.json"
TAG = '<script id="uiInteractionResilienceV32117" src="assets/js/53-ui-interaction-resilience-v32117.js"></script>'

JS = r"""(()=>{
'use strict';
const VERSION='v3.21.17';

function elementFromEvent(event){
  const t=event&&event.target;
  if(t instanceof Element)return t;
  return t&&t.parentElement instanceof Element?t.parentElement:null;
}
function cluster(group){
  return document.querySelector('.nav-cluster[data-cluster="'+CSS.escape(String(group||''))+'"]');
}
function clusterButton(group){
  return document.querySelector('[data-cluster-toggle="'+CSS.escape(String(group||''))+'"]');
}
function setCluster(group,open){
  const c=cluster(group),b=clusterButton(group);
  if(!c||!b)return false;
  c.classList.toggle('open',!!open);
  b.classList.toggle('cluster-open',!!open);
  b.setAttribute('aria-expanded',open?'true':'false');
  return true;
}
function toggleCluster(group){
  const c=cluster(group);
  if(!c)return false;
  const open=!c.classList.contains('open');
  document.querySelectorAll('.nav-cluster[data-cluster]').forEach(node=>{
    const g=node.getAttribute('data-cluster');
    setCluster(g,g===group&&open);
  });
  try{
    if(typeof NAV_V13==='object'&&NAV_V13)NAV_V13.openGroup=open?group:null;
  }catch{}
  try{
    requestAnimationFrame(()=>typeof updateNavPillV12==='function'&&updateNavPillV12(true));
  }catch{}
  return open;
}
function toggleFocusTools(){
  const menu=document.getElementById('focusToolsMenuV171');
  const button=document.getElementById('focusToolsBtnV171');
  if(!menu||!button)return null;
  const open=menu.classList.toggle('open');
  button.setAttribute('aria-expanded',open?'true':'false');
  return open;
}
function captureClick(event){
  const el=elementFromEvent(event);
  if(!el)return;

  const clusterToggle=el.closest('[data-cluster-toggle]');
  if(clusterToggle){
    event.preventDefault();
    event.stopImmediatePropagation();
    toggleCluster(clusterToggle.getAttribute('data-cluster-toggle'));
    return;
  }

  const focusButton=el.closest('#focusToolsBtnV171');
  if(focusButton){
    event.preventDefault();
    event.stopImmediatePropagation();
    toggleFocusTools();
  }
}
document.addEventListener('click',captureClick,true);

function restoreClusterState(snapshot){
  for(const row of snapshot)setCluster(row.group,row.open);
}
function selfTest(){
  const results=[];
  const snapshot=[];
  document.querySelectorAll('[data-cluster-toggle]').forEach(btn=>{
    const group=btn.getAttribute('data-cluster-toggle');
    const c=cluster(group);
    if(!c){
      results.push({name:'cluster-'+group,pass:false,reason:'cluster missing'});
      return;
    }
    snapshot.push({group,open:c.classList.contains('open')});
  });

  for(const row of snapshot){
    const btn=clusterButton(row.group),c=cluster(row.group);
    document.querySelectorAll('.nav-cluster[data-cluster]').forEach(node=>{
      setCluster(node.getAttribute('data-cluster'),false);
    });
    btn.click();
    const opened=c.classList.contains('open')&&btn.getAttribute('aria-expanded')==='true';
    btn.click();
    const closed=!c.classList.contains('open')&&btn.getAttribute('aria-expanded')==='false';
    results.push({name:'cluster-'+row.group,pass:opened&&closed,opened,closed});
  }
  restoreClusterState(snapshot);

  const focusButton=document.getElementById('focusToolsBtnV171');
  const focusMenu=document.getElementById('focusToolsMenuV171');
  if(focusButton&&focusMenu){
    const wasOpen=focusMenu.classList.contains('open');
    if(wasOpen)toggleFocusTools();
    focusButton.click();
    const opened=focusMenu.classList.contains('open')&&focusButton.getAttribute('aria-expanded')==='true';
    focusButton.click();
    const closed=!focusMenu.classList.contains('open')&&focusButton.getAttribute('aria-expanded')==='false';
    if(wasOpen)toggleFocusTools();
    results.push({name:'focus-tools',pass:opened&&closed,opened,closed});
  }else{
    results.push({name:'focus-tools',pass:true,skipped:true,reason:'focus controls not mounted in current view'});
  }

  return {
    version:VERSION,
    pass:results.every(x=>x.pass),
    clusterCount:snapshot.length,
    results
  };
}

window.CELE_UI_INTERACTION_V32117={
  version:VERSION,
  toggleCluster,
  toggleFocusTools,
  selfTest
};
})();"""

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def update_row(rows, path, digest, reason=None):
    found = False
    for row in rows:
        if row.get("path") == path:
            row["sha256"] = digest
            if reason is not None and "reason" in row:
                row["reason"] = reason
            found = True
            break
    if not found:
        row = {"path": path, "sha256": digest}
        if reason is not None:
            row["reason"] = reason
        rows.append(row)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--frontend",required=True)
    ap.add_argument("--report",required=True)
    args=ap.parse_args()

    root=Path(args.frontend).resolve()
    html=root/HTML_REL
    compiler=root/"CELE_PDF_COMPILER_ENGINE_v1_6_1.js"
    manifest_path=root/MANIFEST_REL
    public_path=root/PUBLIC_REL
    js_path=root/JS_REL

    for p in [html,compiler,manifest_path,public_path]:
        if not p.is_file():
            raise SystemExit(f"Missing required baseline file: {p}")
    if sha(html)!=BASE_HTML_SHA:
        raise SystemExit(f"Baseline HTML hash mismatch: {sha(html)}")
    if sha(compiler)!=COMPILER_SHA:
        raise SystemExit("Frozen compiler hash changed before UI patch")
    if js_path.exists():
        raise SystemExit(f"Refusing to overwrite existing {JS_REL}")

    manifest=json.loads(manifest_path.read_text(encoding="utf-8"))
    public=json.loads(public_path.read_text(encoding="utf-8"))
    baseline_manifest=copy.deepcopy(manifest)
    if len(manifest.get("files",[]))!=103:
        raise SystemExit("Expected 103-file v3.21.0 runtime baseline")
    if len(public.get("files",[]))!=112:
        raise SystemExit("Expected 112-file public inclusion baseline")

    js_path.parent.mkdir(parents=True,exist_ok=True)
    js_path.write_text(JS+"\n",encoding="utf-8")

    text=html.read_text(encoding="utf-8")
    if TAG in text:
        raise SystemExit("v3.21.17 script tag already present")
    if "</body>" not in text:
        raise SystemExit("Could not find closing body tag")
    text=text.replace("</body>",TAG+"\n</body>",1)
    html.write_text(text,encoding="utf-8")

    public["version"]="v3.21.17-ui-interaction-resilience"
    update_row(public["files"],HTML_REL,sha(html))
    update_row(public["files"],JS_REL,sha(js_path))
    public_path.write_text(json.dumps(public,indent=2)+"\n",encoding="utf-8")

    reason="Reviewed v3.21.17 UI-interaction resilience patch; CELE data, analytics, engineering logic, and compiler unchanged."
    manifest["frontendVersion"]="v3.21.17-ui-interaction-resilience"
    update_row(manifest["files"],HTML_REL,sha(html),reason)
    update_row(manifest["files"],JS_REL,sha(js_path),reason)
    manifest_path.write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")

    old={x["path"]:x["sha256"] for x in baseline_manifest["files"]}
    new={x["path"]:x["sha256"] for x in manifest["files"]}
    changed=[p for p in old if old[p]!=new.get(p)]
    added=[p for p in new if p not in old]
    unexpected=[p for p in changed if p!=HTML_REL]
    if unexpected or added!=[JS_REL]:
        raise SystemExit(f"Unexpected patch scope: changed={changed}, added={added}")

    report={
        "schemaVersion":1,
        "phase":"v3.21.17-ui-interaction-resilience",
        "status":"PASS",
        "baselineRuntimeFiles":103,
        "patchedRuntimeFiles":len(manifest["files"]),
        "baselinePublicFiles":112,
        "patchedPublicFiles":len(public["files"]),
        "changedBaselineFiles":changed,
        "addedFiles":added,
        "metadataFilesChanged":[PUBLIC_REL,MANIFEST_REL],
        "compilerSha256":sha(compiler),
        "htmlSha256Before":BASE_HTML_SHA,
        "htmlSha256After":sha(html),
        "interactionScriptSha256":sha(js_path),
        "manifestSha256":sha(manifest_path),
        "publicManifestSha256":sha(public_path),
        "scope":{
            "questionDataChanged":False,
            "coverageMathChanged":False,
            "readinessChanged":False,
            "studyNextChanged":False,
            "learnerAnalyticsChanged":False,
            "engineeringCalculationsChanged":False,
            "nscpChanged":False,
            "compilerChanged":False
        }
    }
    out=Path(args.report).resolve()
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(report,indent=2))

if __name__=="__main__":
    main()
