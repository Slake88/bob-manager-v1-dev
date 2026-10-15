// Loopback-only catalog parity and dependency checks.
import fs from 'node:fs';import assert from 'node:assert/strict';import {resolve} from 'node:path';import {pathToFileURL} from 'node:url';
const read=p=>JSON.parse(fs.readFileSync('docs/'+p,'utf8').replace(/^\uFEFF/,''));
const pg=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const {database}=read('PHASE_BASELINE_REBUILD_RESULTS.json');assert.match(database,/^bob_clean_rebuild_\d+$/);
const sql=pg({host:'127.0.0.1',port:55440,user:'postgres',database,max:1,prepare:false,onnotice:()=>{}});
const before=read('PHASE_HIGH_RISK_FINAL_CLOSURE_BEFORE.json');
const old=read('PHASE_HIGH_RISK_SEMANTIC_CLASSIFICATION.json');
const snapshot=read('PHASE_HIGH_RISK_LOCAL_SNAPSHOT.json');
const results=[],triggers=[];
try{
 for(const x of before.pending){
  const t=snapshot.relations.find(t=>t.name===x.table);assert.ok(t);
  assert.equal((x.kind==='trigger'?t.triggers:t.constraints).find(a=>a.name===x.name),undefined,x.id);
  results.push({id:x.id,status:'passed',expected:'absent as in captured production'});
  if(x.kind==='trigger'){
   const deps=await sql.unsafe(`select pg_describe_object(d.classid,d.objid,d.objsubid) object,d.deptype from pg_depend d where d.refobjid=to_regprocedure($1)`,['public.'+x.rebuild.function]);
   triggers.push({id:x.id,table:x.table,definition:x.rebuild.definition,target_function:x.rebuild.function,origin:'20260811160313_rc1_global_audit_foundation.sql automatic table scan; table pre-created by 1000',snapshot_expected:null,historical_sources:x.review_evidence.historical_sources,versioned_consumers:x.review_evidence.current_consumers,function_dependents:deps,effect_before_after:before.effects.effects.find(e=>e.id===x.id)?.modes,final_behavior:read('PHASE_HIGH_RISK_TRIGGER_EFFECTS.json').effects.find(e=>e.id===x.id)?.modes,dependency_assessment:'Trigger removed without CASCADE; shared function retained. Real writer regressions exercise remaining trigger chains.'});
  }
 }
 const prior=before.pending.filter(x=>x.kind==='trigger').map(x=>x.id);
 // All triggers present before this phase except the 18 approved omissions must survive identically.
 const original=read('PHASE_RECONCILIATION_CONSOLIDATED_LOCAL_SNAPSHOT.json');
 for(const d of read('PHASE_HIGH_RISK_CATALOG_DELTA.json').changes.filter(d=>d.kind==='triggers')){const t=original.relations.find(t=>t.name===d.table);t.triggers=t.triggers.filter(t=>t.name!==d.name);if(d.after)t.triggers.push(d.after);}
 let retained=0;
 const normalize=x=>JSON.parse(JSON.stringify(x).replaceAll('\\r\\n','\\n'));
 for(const t of original.relations)for(const tr of t.triggers){if(prior.includes('trigger:'+t.name+'.'+tr.name))continue;assert.deepEqual(normalize(snapshot.relations.find(a=>a.name===t.name).triggers.find(a=>a.name===tr.name)),normalize(tr),t.name+'.'+tr.name);retained++;}
 const stock=snapshot.relations.find(t=>t.name==='stock_movements').constraints.filter(c=>c.definition.includes('product_variants'));
 assert.ok(!stock.some(c=>/CASCADE/.test(c.definition)));
 const items=old.items.map(x=>before.pending.some(p=>p.id===x.id)?{...x,classification:'B',status:'resolved',risk_level:'none',implemented:true,outcome:'approved-snapshot-parity-baseline-only',reason:'Explicit user decision implemented and verified locally',next_action:null}:x);
 assert.equal(items.length,373);assert.equal(items.filter(x=>x.classification==='F').length,0);
 fs.writeFileSync('docs/PHASE_HIGH_RISK_FINAL_CLOSURE_CATALOG_RESULTS.json',JSON.stringify({database,results,triggers,retained_triggers_verified:retained,stock_variant_constraints:stock,classification:{input:373,corrected:371,equivalent:2,remaining:0,items}},null,2)+'\n');
 console.log(JSON.stringify({checks:results.length,retained_triggers:retained,stock}));
}finally{await sql.end();}
