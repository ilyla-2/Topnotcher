import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright-core';

const [url,out]=process.argv.slice(2);
if(!url||!out) throw new Error('usage: node test-large-pdf-intake-v32120.mjs <url> <out>');

const edges=[
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe'
];
const executablePath=edges.find(fs.existsSync);
if(!executablePath) throw new Error('Microsoft Edge executable not found');

const browser=await chromium.launch({headless:true,executablePath,args:['--disable-gpu']});
const page=await browser.newPage({viewport:{width:1440,height:1000}});
const pageErrors=[];
page.on('pageerror',e=>pageErrors.push(String(e?.stack||e)));

await page.goto(url,{waitUntil:'load',timeout:60000});
await page.waitForTimeout(1200);

const result=await page.evaluate(async()=>{
  const api=window.CELE_LARGE_PDF_V32120;
  if(!api) return {api:false};

  const encodingBytes=new Uint8Array(20*1024*1024);
  for(let i=0;i<encodingBytes.length;i+=1048576) encodingBytes[i]=(i/1048576)&255;
  let encodeTicks=0;
  const et=setInterval(()=>encodeTicks++,10);
  const et0=performance.now();
  const encoded=await api.encodeBase64ForTest(new Blob([encodingBytes],{type:'application/pdf'}));
  const encodeMs=performance.now()-et0;
  clearInterval(et);

  const calls=[];
  window.__TAURI__={core:{invoke:async(command,args={})=>{
    calls.push({command,dataLength:typeof args.data==='string'?args.data.length:0});
    if(command==='document_adapter_status') return {ok:true,rendererAvailable:true,ocrAvailable:true,language:'en-US',transport:'tauri-native',backend:'Windows.Data.Pdf + Windows.Media.Ocr',version:'3.21.0',apiVersion:3};
    if(command==='register_source_pdf') return {ok:true,id:'a'.repeat(64),pageCount:120,revision:'stress-r1',preserved:true};
    if(command==='render_source_pdf_page') return {ok:true,base64:'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',width:1,height:1,pageCount:120};
    if(command==='ocr_image_region') return {ok:true,text:'CELE 2026 OCR',lines:[],words:[],bounds:{x:0,y:0,width:1,height:1}};
    return {ok:true};
  }}};

  const bytes=new Uint8Array(10*1024*1024);
  const header=new TextEncoder().encode('%PDF-1.4\n% synthetic large preboard stress fixture\n');
  bytes.set(header,0);
  const file=new File([bytes],'synthetic-preboard-10mb.pdf',{type:'application/pdf'});
  let routeTicks=0;
  const rt=setInterval(()=>routeTicks++,10);
  const rt0=performance.now();
  const routeResult=await api.run(file);
  const routeMs=performance.now()-rt0;
  clearInterval(rt);
  await new Promise(r=>setTimeout(r,100));

  const registerCalls=calls.filter(x=>x.command==='register_source_pdf');
  return {
    api:true,
    version:api.version,
    thresholdBytes:api.thresholdBytes,
    encodeTicks,encodeMs,encodedLength:encoded.length,
    routeTicks,routeMs,routeResult,
    status:api.status(),
    pageBadge:document.getElementById('scanPagesBadge')?.textContent||'',
    registerCalls:registerCalls.length,
    maxRegisteredDataLength:Math.max(0,...registerCalls.map(x=>x.dataLength))
  };
});

await browser.close();

const pass=
  result.api &&
  result.thresholdBytes===8388608 &&
  result.encodeTicks>=2 &&
  result.encodedLength>27000000 &&
  result.status?.lastRoute==='native-large' &&
  result.routeTicks>=1 &&
  result.pageBadge.includes('120') &&
  result.registerCalls===1 &&
  result.maxRegisteredDataLength>13000000 &&
  pageErrors.length===0;

const report={
  phase:'v3.21.20-large-pdf-real-edge-stress',
  status:pass?'PASS':'FAIL',
  ...result,
  pageErrors
};

fs.mkdirSync(path.dirname(out),{recursive:true});
fs.writeFileSync(out,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
if(!pass) process.exit(1);
