// Local-only regression: fixed loopback, disposable database, metadata-only baseline.
// node tools/test_active_membership_phase2c6.mjs <postgres.js/src/index.js> <schema-catalog.json>
import {readFileSync,readdirSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import {restoreCatalog} from './restore_weekly_officer_catalog.mjs';
const postgres=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const options={host:'127.0.0.1',port:55439,user:'postgres',max:1,prepare:false,onnotice:()=>{}};
const root=resolve(import.meta.dirname,'..');
const read=p=>readFileSync(resolve(root,p),'utf8');
const database='bob_phase2c6_'+Date.now();
const admin=postgres({...options,database:'postgres'});
await admin.unsafe(`create database ${database}`); await admin.end();
const client=postgres({...options,database});
const db={exec:s=>client.unsafe(s),query:async(s,p=[])=>({rows:await client.unsafe(s,p)})};
const report={database,endpoint:'127.0.0.1:55439',checks:[]};
try {
 report.catalog=await restoreCatalog(db,JSON.parse(readFileSync(resolve(process.argv[3]),'utf8')));
 // Storage service itself is not emulated; execute the real versioned RLS expressions.
 await db.exec(`create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,owner uuid,owner_id text,metadata jsonb);
 alter table storage.objects enable row level security;
 grant select,insert,update,delete on storage.objects to authenticated;`);
 for(const file of ['20260811184814_rc1_financial_documents_gallery.sql','20260813151451_rc1_fees_operational_hardening.sql']) {
   const source=read('supabase/migrations/'+file);
   const policies=source.match(/create policy (?:financial_documents_\w+|fee_payment_proofs_\w+)[\s\S]*?;/g)||[];
   for(const policy of policies) await db.exec(policy);
 }
 for(const file of readdirSync(resolve(root,'supabase/migrations')).filter(f=>f>='20261013100000' && f<'20261014113517').sort()) await db.exec(read('supabase/migrations/'+file));
 const migration=read('supabase/migrations/20261014113517_rc1_active_membership_personal_access.sql');
 // Baseline expectations must detect the original vulnerability.
 await db.exec('begin;');
 await db.exec(read('supabase/tests/phase2c6_active_membership_regression.sql').split('-- BEGIN ASSERTIONS')[0].replace(/^begin;/m,''));
 await db.exec("update club_memberships set active=false where profile_id=pg_temp.uid(1)");
 assert.equal((await client.unsafe('select financial_request_access_v1(pg_temp.id(4,1)) as allowed'))[0].allowed,true);
 await db.exec('rollback;');
 report.checks.push('Baseline reproduces inactive-owner financial access');
 const functions=()=>client.unsafe(`select p.oid,p.proname,pg_get_functiondef(p.oid) definition,p.proacl::text acl,pg_get_function_arguments(p.oid) args,p.prorettype,p.proretset,p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','bob_fees_private') order by p.oid`);
 const baselineFunctions=await functions();
 await db.exec(migration);
 const changedNames=new Set(['current_financial_member_v1','financial_request_access_v1','current_weekly_officer_member_v1','fee_credit_balance_v1','cancel_reported_fee_payment_v1','acknowledge_event_task_v1','set_event_shift_member_status_v1','withdraw_event_proposal_v1']);
 const candidateFunctions=await functions();
 assert.equal(candidateFunctions.length,baselineFunctions.length);
 for(let i=0;i<baselineFunctions.length;i++) {
  const old=baselineFunctions[i],current=candidateFunctions[i];
  if(!changedNames.has(old.proname)) assert.deepEqual(current,old);
  else for(const key of ['oid','args','prorettype','proretset','prosecdef','acl']) assert.deepEqual(current[key],old[key],old.proname+' '+key);
 }
 report.checks.push('All function contracts/ACLs preserved; functions outside eight targets unchanged');
 await db.exec(read('supabase/tests/phase2c6_active_membership_regression.sql'));
 report.checks.push('SQL matrix: active/inactive/missing identity/no membership, owner/third party/two clubs/managers, RPCs, direct RLS, Storage, unchanged rejection, ACL/search_path');
 const before=await client.unsafe(`select n.nspname,p.proname,pg_get_functiondef(p.oid) definition,p.proacl::text acl from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' order by p.oid`);
 await db.exec(migration);
 assert.deepEqual(await client.unsafe(`select n.nspname,p.proname,pg_get_functiondef(p.oid) definition,p.proacl::text acl from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' order by p.oid`),before);
 await db.exec(read('supabase/tests/phase2c6_active_membership_regression.sql'));
 report.checks.push('Identical function definitions/ACLs after reapplication; full regression passes twice');
 // Reapply with populated tables: every row (including audit/notifications/Storage) is identical.
 await db.exec(read('supabase/tests/phase2c6_active_membership_regression.sql').split('-- BEGIN ASSERTIONS')[0]+'commit;');
 const snapshot=async()=>JSON.stringify(await client.unsafe(`select relname, (xpath('/row/data/text()',query_to_xml(format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) data from %I.%I t',schemaname,relname),false,true,'')))[1]::text data from (select schemaname,tablename relname from pg_tables where schemaname in ('public','storage')) x order by schemaname,relname`));
 const rowsBefore=await snapshot(); await db.exec(migration); assert.equal(await snapshot(),rowsBefore);
 report.checks.push('Reapplication with populated synthetic tables changes zero business/audit/notification/Storage rows');
 report.status='passed'; console.log(JSON.stringify(report,null,2));
} catch(e) {report.status='failed';report.error={message:e.message,code:e.code,where:e.where};throw e;}
finally {writeFileSync(resolve(root,'docs/PHASE_2C6_SQL_RESULTS.json'),JSON.stringify(report,null,2)+'\n');await client.end({timeout:5});}
