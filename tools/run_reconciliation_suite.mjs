// Run in an isolated copy: harnesses write local evidence. No remote connection.
// node tools/run_reconciliation_suite.mjs <postgres-driver-entry>
import {pathToFileURL} from 'node:url';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {sanitizeCatalog} from './sanitize_catalog.mjs';
const root=resolve(import.meta.dirname,'..'),driver=resolve(process.argv[2]);
const hash=x=>createHash('sha256').update(x).digest('hex');
const fixture=readFileSync(resolve(root,'tools/fixtures/reconciliation_catalog.json'));
assert.equal(hash(fixture),JSON.parse(readFileSync(resolve(root,'tools/fixtures/reconciliation_catalog.provenance.json'))).fixture_sha256);
const syntheticEndpoint=name=>'https://'+name+'.supabase.co/functions/v1/test';
assert.deepEqual(sanitizeCatalog({captured_at:'clock',version:'build',body:syntheticEndpoint('synthetic-a')}),sanitizeCatalog({captured_at:'other',version:'other',body:syntheticEndpoint('synthetic-b')}));
const names=['test_clean_rebuild','test_policy_hardening','test_ambiguous_address','test_ambiguous_override','test_consolidated_preflight','test_consolidated_writers','test_final_contracts','test_final_policies','test_grouped_fees','test_grouped_memberships','test_grouped_operations','test_high_risk','test_high_risk_closure','test_policy_documents','test_policy_structural_contracts','test_structural_blockers','test_structural_drift','test_final_event_policies','test_reconciliation','test_reconciliation_final'];
const report={status:'running',scope:'18 original checks including replay, plus two catalog restore harnesses; loopback only',fixture_sha256:hash(fixture),external_catalog_dependency:'Eliminated at runtime using versioned frozen schema fixture; historical provenance retained',rounds:[],snapshot_hashes:[],isolated_hashes:[]};
let invocation=0;
process.chdir(root);
async function run(name){
 process.argv=[process.execPath,resolve(root,'tools/'+name+'.mjs'),driver,...(name==='test_clean_rebuild'?['--allow-extension-adapters']:[])];
 process.exitCode=0;
 let error;
 try {await import(pathToFileURL(process.argv[1]).href+'?invocation='+invocation++);}catch(e){error=e.code||e.message;process.exitCode=1;}
 const exit=process.exitCode||0;
 console.log(name,exit,error||'');
 return {harness:name,exit,status:exit===0?'passed':'failed',...(error?{error}:{})};
}
for(let i=0;i<2;i++){
 const round=[];for(const name of names)round.push(await run(name));report.rounds.push(round);
 report.snapshot_hashes.push(hash(readFileSync(resolve(root,'docs/PHASE_HIGH_RISK_LOCAL_SNAPSHOT.json'))));
}
const isolated=[];for(const name of ['test_structural_drift','test_high_risk','test_high_risk_closure','test_reconciliation','test_reconciliation_final'])isolated.push(await run(name));
report.isolated_cases=isolated;
report.isolated_hashes.push(hash(readFileSync(resolve(root,'docs/PHASE_HIGH_RISK_LOCAL_SNAPSHOT.json'))));
report.snapshot_byte_identical=new Set([...report.snapshot_hashes,...report.isolated_hashes]).size===1;
const replay=JSON.parse(readFileSync(resolve(root,'docs/PHASE_BASELINE_REBUILD_RESULTS.json')));
report.replay={total:replay.total,applied:replay.applied.length,status:replay.status,adapters:true};
report.status=report.rounds.flat().concat(isolated).every(x=>x.exit===0)&&report.snapshot_byte_identical&&replay.applied.length===154?'passed':'failed';
writeFileSync(resolve(root,'docs/PHASE_RECONCILIATION_REPRODUCIBILITY_RESULTS.json'),JSON.stringify(report,null,2)+'\n');
process.exitCode=report.status==='passed'?0:1;
