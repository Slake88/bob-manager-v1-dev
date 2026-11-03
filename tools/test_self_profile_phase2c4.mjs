// Local PostgreSQL only; fixed loopback and fresh database, no remote URL accepted.
// Usage: node tools/test_self_profile_phase2c4.mjs <postgres.js/src/index.js> <schema-catalog.json>
import {readFileSync,readdirSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import {restoreCatalog} from './restore_weekly_officer_catalog.mjs';
const postgres=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const options={host:'127.0.0.1',port:55439,user:'postgres',max:1,prepare:false,onnotice:()=>{}};
const admin=postgres({...options,database:'postgres'});
const database='bob_phase2c4_'+Date.now();
await admin.unsafe(`create database ${database}`); await admin.end();
const client=postgres({...options,database});
const db={exec:s=>client.unsafe(s),query:async(s,p=[])=>({rows:await client.unsafe(s,p)})};
const root=resolve(import.meta.dirname,'..');
const read=p=>readFileSync(resolve(root,p),'utf8');
const migration=s=>read('supabase/migrations/'+readdirSync(resolve(root,'supabase/migrations')).find(f=>f.endsWith(s)));
const report={database,endpoint:'127.0.0.1:55439',checks:[]};
const pass=s=>{report.checks.push(s);console.log('PASS '+s);};
const failMigration=async(sql,code)=>{
  await assert.rejects(db.exec(sql),e=>e.code===code);
  await db.exec('rollback');
};
try {
  report.catalog=await restoreCatalog(db,JSON.parse(readFileSync(resolve(process.argv[3]),'utf8')));
  await db.exec(read('supabase/migrations/20261013100000_rc1_authenticated_security_definer_phase2c_low_risk.sql'));
  await db.exec(migration('_rc1_self_profile_permission_and_cardinality.sql'));
  await db.exec(read('supabase/tests/phase2c4_self_profile_regression.sql'));
  pass('Both RPCs: auth/access/permission, exact cardinality, ACLs, fields and audit; regression rollback');
  const index=migration('_rc1_members_unique_club_profile.sql');
  await db.exec(`insert into auth.users(id) values ('10000000-0000-0000-0000-000000000001');
    insert into clubs(id,name,slug) values ('00000000-0000-0000-0000-000000000001','Fixture','fixture');
    insert into profiles(id,full_name,email) values ('10000000-0000-0000-0000-000000000001','Fixture','fixture@example.invalid');
    insert into club_memberships(club_id,profile_id,active,access_role) values ('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',true,'member');
    select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',false);
    insert into members(club_id,profile_id,full_name,status) select '00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',x,'active' from unnest(array['A','B']) x;`);
  const snapshot=async()=>JSON.stringify((await db.query(`select jsonb_build_object('members',(select jsonb_agg(to_jsonb(m) order by id) from members m),'audit',(select count(*) from audit_log)) as data`)).rows[0].data);
  const before=await snapshot();
  await failMigration(index,'23505');
  assert.equal(await snapshot(),before);
  assert.equal((await db.query("select to_regclass('public.members_club_profile_unique') as idx")).rows[0].idx,null);
  pass('Duplicate preflight aborts without altering rows/audit or creating index');
  await db.exec(`update members set profile_id=null where full_name='B'; create index members_club_profile_unique on members(club_id);`);
  await failMigration(index,'55000');
  pass('Incompatible named index fails safely');
  await db.exec('drop index members_club_profile_unique');
  const clean=await snapshot();
  await db.exec(index); await db.exec(index);
  assert.equal(await snapshot(),clean);
  await db.exec(read('supabase/tests/phase2c4_self_profile_index_regression.sql'));
  pass('Unique partial index: idempotence, duplicate rejection, null links and cross-club links');
  await db.exec(migration('_rc1_self_profile_permission_and_cardinality.sql'));
  assert.equal(await snapshot(),clean);
  pass('RPC migration reapplication preserves rows/audit');
  report.status='passed';
} catch(e) {report.status='failed';report.error={message:e.message,code:e.code};throw e;}
finally {writeFileSync(resolve(root,'docs/PHASE_2C4_SQL_RESULTS.json'),JSON.stringify(report,null,2));await client.end({timeout:5});}
