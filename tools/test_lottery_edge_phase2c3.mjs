// Executes the Edge Function handler in a sandbox with mocked Supabase/fetch.
// No Deno credentials, production endpoints or network requests are used.
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {stripTypeScriptTypes} from 'node:module';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const root=resolve(import.meta.dirname,'..');
let source=readFileSync(resolve(root,'supabase/functions/euromillions-official-import/index.ts'),'utf8');
source=source.replace(/^import .*;\r?\n/gm,'');
let handler;let allowed=false;let validUser=true;const calls=[];
const context={Request,Response,Intl,Date,console,
 fetch:()=>{throw new Error('Unexpected network request');},
 Deno:{serve:h=>{handler=h;},env:{get:key=>{calls.push(['env',key]);return key==='SUPABASE_URL'?'https://example.invalid':'dummy';}}},
 createClient:()=>({auth:{getUser:async()=>({data:{user:validUser?{id:'fixture'}:null},error:null})},
 rpc:async(name,params)=>{calls.push([name,params]);return {data:allowed,error:null};},
 from:()=>{throw new Error('Unexpected data access');}}),
};
vm.runInNewContext(stripTypeScriptTypes(source,{mode:'transform'}),context);
const run=async(year,month,auth=true)=>{calls.length=0;return handler(new Request('https://example.invalid/import',{
 method:'POST',headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer fixture'}:{})},
 body:JSON.stringify({club_id:'fixture',year,month})}));};
const checks=[];
const check=(v,s)=>{assert.ok(v,s);checks.push(s);console.log('PASS '+s);};
check((await run(2030,1,false)).status===401,'Missing identity rejected before any data access');
check((await run(2030,1)).status===403,'Viewer cannot import');
check(calls.some(c=>c[0]==='has_club_permission'&&c[1].requested_permission==='manageLottery'),'Server checks manageLottery');
allowed=true;
check((await run(2020,1)).status===400,'Past import rejected server-side');
check(!calls.some(c=>c[1]==='SUPABASE_SERVICE_ROLE_KEY'),'Past import never requests privileged credentials');
check((await run(99999,1)).status===400,'Invalid year rejected');
const future=new Date().getFullYear()+1;
check((await run(future,1)).status===200,'Manager may explicitly request a future month (no completed draws)');
check(!calls.some(c=>c[1]==='SUPABASE_SERVICE_ROLE_KEY'),'Empty future month does not use privileged processing');
writeFileSync(resolve(root,'docs/PHASE_2C3_EDGE_RESULTS.json'),JSON.stringify({status:'passed',checks,network:'mocked; no real HTTP'},null,2));
