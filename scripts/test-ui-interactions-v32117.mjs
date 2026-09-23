import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright-core';

const url=process.argv[2];
const out=process.argv[3];
if(!url||!out) throw new Error('usage: node test-ui-interactions-v32117.mjs <url> <out>');

const candidates=[
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe'
];
const executablePath=candidates.find(p=>fs.existsSync(p));
if(!executablePath) throw new Error('Microsoft Edge executable not found');

const browser=await chromium.launch({headless:true,executablePath,args:['--disable-gpu']});
const page=await browser.newPage({viewport:{width:1440,height:1000}});
const pageErrors=[];
const consoleErrors=[];
page.on('pageerror',e=>pageErrors.push(String(e?.stack||e)));
page.on('console',m=>{if(m.type()==='error')consoleErrors.push(m.text())});

await page.goto(url,{waitUntil:'load',timeout:60000});
await page.waitForTimeout(1500);

const report=await page.evaluate(()=>{
  const api=window.CELE_UI_INTERACTION_V32117;
  return {
    apiPresent:!!api,
    test:api?.selfTest?.()||null,
    handlers:{
      practice:document.querySelector('[data-cluster-toggle="practice"]')?.getAttribute('aria-expanded')??null,
      progress:document.querySelector('[data-cluster-toggle="progress"]')?.getAttribute('aria-expanded')??null,
      sources:document.querySelector('[data-cluster-toggle="sources"]')?.getAttribute('aria-expanded')??null,
      system:document.querySelector('[data-cluster-toggle="system"]')?.getAttribute('aria-expanded')??null
    }
  };
});
await browser.close();

const result={
  phase:'v3.21.17-real-browser-ui-interaction',
  status:report.apiPresent&&report.test?.pass&&report.test?.clusterCount>=4?'PASS':'FAIL',
  ...report,
  pageErrors,
  consoleErrors
};
fs.mkdirSync(path.dirname(out),{recursive:true});
fs.writeFileSync(out,JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result,null,2));
if(result.status!=='PASS')process.exit(1);
