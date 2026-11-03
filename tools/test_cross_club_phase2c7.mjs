// Fixed loopback only. Fresh disposable PostgreSQL; catalog contains schema, no data.
// node tools/test_cross_club_phase2c7.mjs <postgres.js/src/index.js> <schema-catalog.json>
import {readFileSync,readdirSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import {restoreCatalog} from './restore_weekly_officer_catalog.mjs';
const postgres=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const options={host:'127.0.0.1',port:55440,user:'postgres',max:1,prepare:false,onnotice:()=>{}};
const root=resolve(import.meta.dirname,'..');
const read=p=>readFileSync(resolve(root,p),'utf8');
const database='bob_phase2c7_'+Date.now();
const admin=postgres({...options,database:'postgres'});
await admin.unsafe(`create database ${database}`); await admin.end();
const client=postgres({...options,database});
const db={exec:s=>client.unsafe(s),query:async(s,p=[])=>({rows:await client.unsafe(s,p)})};
const report={database,endpoint:'127.0.0.1:55440',checks:[]};
const names=['create_treasury_transaction','create_member_with_position','asset_loan_v1','log_asset_event_v1','create_shop_order_v1'];
const functions=()=>client.unsafe(`select p.oid,p.proname,pg_get_functiondef(p.oid) definition,p.proacl::text acl,pg_get_function_arguments(p.oid) args,p.prorettype,p.proretset,p.prosecdef,p.proowner,p.provolatile,p.proparallel,p.proisstrict,p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','bob_fees_private') order by p.oid`);
const snapshot=async()=>JSON.stringify(await client.unsafe(`select schemaname,tablename, (xpath('/row/data/text()',query_to_xml(format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) data from %I.%I t',schemaname,tablename),false,true,'')))[1]::text data from pg_tables where schemaname in ('public','net','storage') order by schemaname,tablename`));
try {
 report.catalog=await restoreCatalog(db,JSON.parse(readFileSync(resolve(process.argv[3]),'utf8')));
 await db.exec(`create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,owner uuid,owner_id text,metadata jsonb); alter table storage.objects enable row level security; grant select,insert,update,delete on storage.objects to authenticated;`);
 for(const file of readdirSync(resolve(root,'supabase/migrations')).filter(f=>f>='20261013100000' && f<'20261014133347').sort()) await db.exec(read('supabase/migrations/'+file));
 const migration=read('supabase/migrations/20261014133347_rc1_cross_club_references.sql');
 const sql=read('supabase/tests/phase2c7_cross_club_references_regression.sql');
 const fixtures=sql.split('-- BEGIN ASSERTIONS')[0];
 const helper=sql.split('-- BEGIN ASSERTIONS')[1].split('do $$ declare r record;')[0];
 // Reproduce all eight absent club checks and confirm valid/NULL behavior before replacing functions.
 await db.exec(fixtures+helper);
 const cases=await client.unsafe('select * from cases');
 report.caseCount=cases.length;
 for(const c of cases.filter(c=>c.message===null || c.label.endsWith(' cross'))) {
  await client.unsafe('select pg_temp.attempt($1,null,$2)',[c.stmt,c.verify]);
 }
 // Capture original permission failures for all cases, including malformed UUID references.
 const permissionErrors=[];
 for(const uid of ['00000001-0000-0000-0000-000000000002','']) {
  await client.unsafe("select set_config('request.jwt.claim.sub',$1,true)",[uid]);
  for(const c of cases) {
   await db.exec('savepoint denied');
   await db.exec('set local role authenticated');
   try {await db.exec(c.stmt);assert.fail('Unauthorized success');}
   catch(e) {assert.equal(e.code,'P0001');permissionErrors.push({label:c.label,uid,code:e.code,message:e.message});}
   finally {await db.exec('rollback to savepoint denied');}
  }
 }
 await db.exec('rollback');
 report.checks.push('Baseline reproduces cross-club acceptance for eight references (plus both borrower fields regardless of type); valid/NULL fixtures pass');
 const baselineFunctions=await functions();
 // Preflight must abort atomically on absent functions or unexpected PUBLIC exposure.
 const bareMigration=migration.replace(/^begin;/,'').replace(/commit;\s*$/,'');
 for(const [tamper,expected] of [
  ['drop function public.log_asset_event_v1(uuid,uuid,text,text,text,jsonb)','42883'],
  ['grant execute on function public.log_asset_event_v1(uuid,uuid,text,text,text,jsonb) to public','42501']
 ]) {
  await db.exec('begin');
  await db.exec(tamper);
  let rejected=false;
  try {await db.exec(bareMigration);} catch(e) {assert.equal(e.code,expected);rejected=true;}
  finally {await db.exec('rollback');}
  assert.equal(rejected,true); assert.deepEqual(await functions(),baselineFunctions);
 }
 report.checks.push('Preflight rejects absent RPCs and unexpected PUBLIC exposure atomically; original catalog fully restored');
 const rowsBefore=await snapshot();
 await db.exec(migration);
 assert.equal(await snapshot(),rowsBefore);
 const candidateFunctions=await functions();
 assert.equal(candidateFunctions.length,baselineFunctions.length);
 for(let i=0;i<baselineFunctions.length;i++) {
  const old=baselineFunctions[i],current=candidateFunctions[i];
  if(!names.includes(old.proname)) assert.deepEqual(current,old);
  else {
   for(const key of Object.keys(old).filter(k=>!['definition','proconfig'].includes(k))) assert.deepEqual(current[key],old[key],old.proname+' '+key);
   assert.deepEqual(current.proconfig,['search_path=pg_catalog, public, pg_temp']);
   const privileges=(await client.unsafe(`select has_function_privilege('anon',$1::oid,'EXECUTE') anon,has_function_privilege('authenticated',$1::oid,'EXECUTE') authenticated,has_function_privilege('service_role',$1::oid,'EXECUTE') service, exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) where grantee=0 and privilege_type='EXECUTE') public from pg_proc p where p.oid=$1::oid`,[current.oid]))[0];
   assert.deepEqual(privileges,{anon:false,authenticated:true,service:true,public:false});
  }
 }
 report.checks.push('Only five definitions changed; OIDs, exact signatures/defaults, owner, ACLs, volatility/strictness/parallelism preserved; PUBLIC/anon denied');
 await db.exec(sql);
 report.checks.push('Full SQL matrix passed: valid, missing, foreign, NULL, inactive references, all borrower types, transfer/accounts, product/variant guards, unauthorized/no identity/anon; every case rolls back all public/net rows');
 await db.exec(fixtures);
 const populated=await snapshot();
 for(const e of permissionErrors) {
  await client.unsafe("select set_config('request.jwt.claim.sub',$1,true)",[e.uid]);
  await db.exec('savepoint denied'); await db.exec('set local role authenticated');
  try {await db.exec(cases.find(c=>c.label===e.label).stmt);assert.fail('Unauthorized success');}
  catch(error) {assert.equal(error.code,e.code);assert.equal(error.message,e.message);}
  finally {await db.exec('rollback to savepoint denied');}
 }
 assert.equal(await snapshot(),populated);
 await db.exec('rollback');
 report.checks.push('Exact baseline authorization errors preserved for every reference case, absent identity and no-permission member');
 // Reapplication on populated synthetic tables must leave every row and definition unchanged.
 await db.exec(fixtures+'commit;');
 // A second local connection must not move a newly validated reference between clubs.
 const contender=postgres({...options,database});
 try {
  for(const [table,k,label] of [['treasury_categories',5,'treasury'],['cost_centers',6,'treasury'],['events',4,'treasury'],['club_positions',7,'member'],['members',3,'shop'],['inventory_assets',8,'log']]) {
   await db.exec('begin');
   await db.exec("select set_config('request.jwt.claim.sub','00000001-0000-0000-0000-000000000001',true)");
   await db.exec('set local role authenticated');
   await db.exec(cases.find(c=>c.label.startsWith(label+' same club')).stmt);
   await contender.unsafe('begin');
   const contenderPid=(await contender.unsafe('select pg_backend_pid() pid'))[0].pid;
   const pending=contender.unsafe(`update public.${table} set club_id='00000002-0000-0000-0000-000000000002' where id=$1::uuid`,[`${String(k).padStart(8,'0')}-0000-0000-0000-000000000001`]).then(()=>({ok:true}),error=>({error}));
   try {
    await db.exec('reset role');
    let blocked=false;
    for(let i=0;i<100;i++) {
     const state=(await client.unsafe('select wait_event_type from pg_stat_activity where pid=$1::integer',[contenderPid]))[0];
     if(state?.wait_event_type==='Lock') {blocked=true;break;}
     await new Promise(resolve=>setTimeout(resolve,25));
    }
    assert.equal(blocked,true,'Concurrent club_id update must wait: '+table);
   } finally {
    // Release the checked SHARE lock; then discard the competitor's whole transaction.
    await db.exec('rollback');
    const outcome=await pending;
    if(outcome.error) assert.equal(outcome.error.code,'23505',table); // fixtures share club-local names
    await contender.unsafe('rollback');
   }
  }
 } finally {await contender.end({timeout:5});}
 report.checks.push('Two-connection tests: SHARE locks block concurrent club_id reassignment in all six newly validated reference tables');
 const populatedBefore=await snapshot(); const defs=await functions();
 await db.exec(migration);
 assert.equal(await snapshot(),populatedBefore); assert.deepEqual(await functions(),defs);
 await db.exec('begin; truncate '+(await client.unsafe("select schemaname,tablename from pg_tables where schemaname in ('public','net','auth')")).map(t=>`"${t.schemaname}"."${t.tablename}"`).join(',')+' cascade; commit;');
 await db.exec('drop function pg_temp.id(integer,integer); drop function pg_temp.assert(boolean,text); drop function pg_temp.snapshot(); drop table cases;');
 await db.exec(sql);
 report.checks.push('Idempotent reapplication on populated fixtures changes zero rows; full regression passes twice');
 report.status='passed'; console.log(JSON.stringify(report,null,2));
} catch(e) {report.status='failed';report.error={message:e.message,code:e.code,where:e.where};console.error(report.error);process.exitCode=1;}
finally {writeFileSync(resolve(root,'docs/PHASE_2C7_SQL_RESULTS.json'),JSON.stringify(report,null,2)+'\n');await client.end({timeout:5});}
