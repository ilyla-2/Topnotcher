import fs from 'node:fs';import path from 'node:path';import {chromium} from 'playwright-core';
const [url,out]=process.argv.slice(2);if(!url||!out)throw new Error('usage');
const edges=['C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe','C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe'];const executablePath=edges.find(fs.existsSync);if(!executablePath)throw new Error('Edge missing');
const browser=await chromium.launch({headless:true,executablePath,args:['--disable-gpu']});const page=await browser.newPage({viewport:{width:1440,height:1000}});
const pageErrors=[];const consoleErrors=[];page.on('pageerror',e=>pageErrors.push(String(e?.stack||e)));page.on('console',m=>{if(m.type()==='error')consoleErrors.push(m.text())});
await page.goto(url,{waitUntil:'load',timeout:60000});await page.waitForTimeout(1800);
const result=await page.evaluate(async()=>{
 const groups=['practice','progress','sources','system'];
 const originalHandlers=Object.fromEntries(groups.map(g=>[g,typeof document.querySelector('[data-cluster-toggle="'+g+'"]')?.onclick==='function']));
 const resilience=window.CELE_UI_INTERACTION_V32117?.selfTest?.()||null;
 const wrappers={range:typeof window.clampScanRangeV12==='function',current:typeof window.nativeOcrCurrentScanPage==='function',all:typeof window.nativeOcrAllScanPages==='function',api:!!window.CELE_OCR_UI_WIRE_V32118};
 let noFileClick=true;let clickError=null;
 try{document.getElementById('scanNativeOcrBtn')?.click();await new Promise(r=>setTimeout(r,50));}catch(e){noFileClick=false;clickError=String(e)}
 return {groups,originalHandlers,resilience,wrappers,noFileClick,clickError};
});
await browser.close();
const pass=result.groups.every(g=>result.originalHandlers[g])&&result.resilience?.pass&&result.wrappers.range&&result.wrappers.current&&result.wrappers.all&&result.wrappers.api&&result.noFileClick&&pageErrors.length===0;
const report={phase:'v3.21.18-real-browser-startup-rootfix',status:pass?'PASS':'FAIL',...result,pageErrors,consoleErrors};
fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));if(!pass)process.exit(1);
