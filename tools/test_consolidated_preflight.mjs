import {readFileSync,writeFileSync} from 'node:fs';import {resolve} from 'node:path';import {pathToFileURL} from 'node:url';import assert from 'node:assert/strict';
const pg=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const {database}=JSON.parse(readFileSync('docs/PHASE_BASELINE_REBUILD_RESULTS.json'));assert.match(database,/^bob_clean_rebuild_\d+$/);
const sql=pg({host:'127.0.0.1',port:55440,user:'postgres',database,max:1,prepare:false,onnotice:()=>{}});
const report={database,endpoint:'127.0.0.1:55440',production_executed:false};
try{const results=await sql.unsafe(readFileSync('docs/PHASE_RECONCILIATION_FINAL_INCREMENTAL_PREFLIGHT.sql','utf8'));report.status='passed';report.result_sets=results.length;report.note='Read-only SQL syntax/catalog compatibility on clean PostgreSQL + adapters only; no production assertion';}
catch(e){report.status='failed';report.error={code:e.code,message:e.message};process.exitCode=1;}
finally{await sql.unsafe('rollback').catch(()=>{});await sql.end();writeFileSync('docs/PHASE_RECONCILIATION_CONSOLIDATED_PREFLIGHT_RESULTS.json',JSON.stringify(report,null,2)+'\n');}
console.log(JSON.stringify(report));
