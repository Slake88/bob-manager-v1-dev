// In-memory PostgreSQL only. No connection URL, Supabase client, or credentials.
// Pass an installed @electric-sql/pglite module path as the first argument.
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
import { restoreCatalog } from './restore_weekly_officer_catalog.mjs';
const native = process.argv.includes('--native');
const catalogPath = process.argv.includes('--catalog')
  ? process.argv[process.argv.indexOf('--catalog')+1] : null;
let restoredCatalog;
let db;
let nativeConnect;
if (native) {
  const postgres = (await import(pathToFileURL(resolve(process.argv[2])).href)).default;
  const options = {host:'127.0.0.1',port:55439,user:'postgres',prepare:false,max:1,onnotice:()=>{}};
  const admin = postgres({...options,database:'postgres'});
  const database = 'bob_phase2c2_module_'+Date.now();
  await admin.unsafe(`create database ${database}`);
  await admin.end();
  nativeConnect = () => postgres({...options,database});
  const client=nativeConnect();
  db={exec:sql=>client.unsafe(sql),query:async(sql,params=[])=>({rows:await client.unsafe(sql,params)}),close:()=>client.end({timeout:5})};
  console.log('Native fixture database: '+database);
} else {
  const { PGlite } = await import(pathToFileURL(resolve(process.argv[2])).href);
  db = new PGlite();
}
const root = resolve(import.meta.dirname, '..');
const read = path => readFileSync(resolve(root, path), 'utf8');
const original = read('supabase/migrations/20260812085920_rc1_weekly_officer_dinner_roster.sql');
const base = read('supabase/migrations/1000_bob_manager_v1_complete.sql');
const extract = name => base.match(new RegExp('create or replace function public\\.'+name+'\\([\\s\\S]*?\\$\\$;'))[0];
if(catalogPath) {
  assert.ok(native,'Catalog tests require native local PostgreSQL');
  restoredCatalog=await restoreCatalog(db,JSON.parse(readFileSync(resolve(catalogPath),'utf8')));
  console.log('Restored production schema metadata: '+JSON.stringify(restoredCatalog));
} else {
await db.exec(`
do $$ begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
end $$;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
grant usage on schema auth to authenticated,anon,service_role;
create table clubs(id uuid primary key, name text);
create table profiles(id uuid primary key, full_name text);
create table club_memberships(id uuid default gen_random_uuid(),club_id uuid,profile_id uuid,active boolean,access_role text);
create table members(id uuid primary key,club_id uuid references clubs,profile_id uuid,member_number integer,
 full_name text,nickname text,status text,primary_role text,created_at timestamptz default now());
create table notification_preferences(club_id uuid,profile_id uuid,module_code text,in_app_enabled boolean);
create table notifications(club_id uuid,profile_id uuid,title text,body text,notification_type text,module_code text,
 priority text,entity_type text,entity_id uuid,action_route text,metadata jsonb);
create table audit_log(club_id uuid,actor_profile_id uuid,action text,entity_type text,entity_id text,
 old_data jsonb,new_data jsonb,reason text,created_at timestamptz);
${extract('has_club_access')}
${extract('audit_event')}
`);
await db.exec(original);
await db.exec(read('supabase/migrations/20260812091054_rc1_weekly_officer_security_hardening.sql'));
await db.exec(read('supabase/migrations/20260812091155_rc1_weekly_officer_history_guard.sql'));
if(native) {
  await db.exec('alter table audit_log add column actor_id uuid,add column before_data jsonb,add column after_data jsonb,add column data jsonb');
  const audit=read('supabase/migrations/20260811160313_rc1_global_audit_foundation.sql');
  for(const name of ['audit_redact_json_v1','audit_stamp_row_v1','audit_capture_row_v1']) {
    await db.exec(audit.match(new RegExp('create or replace function public\\.'+name+'\\([\\s\\S]*?\\$\\$;'))[0]);
  }
  await db.exec(read('supabase/migrations/20260906202000_rc1_audit_event_reason.sql'));
  for(const table of ['weekly_dinners','weekly_officer_absences','weekly_officer_rotation','weekly_officer_swap_requests']) {
    await db.exec(`create trigger trg_audit_stamp_v1 before insert or update on ${table} for each row execute function audit_stamp_row_v1();
    create trigger trg_audit_capture_v1 after insert or update or delete on ${table} for each row execute function audit_capture_row_v1();`);
  }
}
}
const file = readdirSync(resolve(root,'supabase/migrations')).find(p=>p.endsWith('_rc1_weekly_officer_calendar_assignment_split.sql'));
// A populated-state reapplication is checked below.
const club='00000000-0000-0000-0000-000000000001';
const other='00000000-0000-0000-0000-000000000002';
const manager='10000000-0000-0000-0000-000000000001';
const member='10000000-0000-0000-0000-000000000002';
const outsider='10000000-0000-0000-0000-000000000003';
const a='20000000-0000-0000-0000-000000000001';
const b='20000000-0000-0000-0000-000000000002';
if(catalogPath) await db.exec(`insert into auth.users(id) values('${manager}'),('${member}'),('${outsider}');`);
await db.exec(catalogPath ? `insert into clubs(id,name,slug) values('${club}','Fixture','fixture-a'),('${other}','Other','fixture-b');
insert into profiles(id,full_name,email) values('${manager}','Manager','manager@example.invalid'),('${member}','Member','member@example.invalid'),('${outsider}','Outsider','outsider@example.invalid');` :
`insert into clubs values('${club}','Fixture'),('${other}','Other');
insert into profiles values('${manager}','Manager'),('${member}','Member'),('${outsider}','Outsider');`);
await db.exec(`
insert into club_memberships(club_id,profile_id,active,access_role) values
('${club}','${manager}',true,'president'),('${club}','${member}',true,'member'),('${other}','${outsider}',true,'president');
select set_config('request.jwt.claim.sub','${manager}',false);
insert into members(id,club_id,profile_id,full_name,status) values
('${a}','${club}','${manager}','A','active'),('${b}','${club}','${member}','B','active');`);
const beforeReapply=(await db.query('select jsonb_agg(to_jsonb(r) order by id) snapshot from weekly_officer_rotation r')).rows[0].snapshot;
let beforeFirstApply;
if(catalogPath) {
  await db.exec(`insert into weekly_dinners(club_id,dinner_date,dinner_kind,status,assigned_member_id,assignment_source,generated)
    values('${club}','2019-01-03','regular','planned','${a}','auto',true),
    ('${club}','2019-01-10','regular','completed','${b}','manual',false);`);
  beforeFirstApply=(await db.query(`select jsonb_build_object(
    'dinners',(select jsonb_agg(to_jsonb(d) order by id) from weekly_dinners d),
    'rotation',(select jsonb_agg(to_jsonb(d) order by id) from weekly_officer_rotation d),
    'audit_count',(select count(*) from audit_log)) snapshot`)).rows[0].snapshot;
}
await db.exec(read('supabase/migrations/'+file));
assert.deepEqual((await db.query('select jsonb_agg(to_jsonb(r) order by id) snapshot from weekly_officer_rotation r')).rows[0].snapshot,beforeReapply);
const [{year}] = (await db.query('select extract(year from current_date)::integer+1 as year')).rows;
let checks=0;
const messages=[];
const check = (value,message) => { assert.ok(value,message); checks++; messages.push(message); console.log('PASS '+message); };
const scalar = async (query,params=[]) => Object.values((await db.query(query,params)).rows[0])[0];
if(catalogPath) {
  const afterFirstApply=await scalar(`select jsonb_build_object(
    'dinners',(select jsonb_agg(to_jsonb(d) order by id) from weekly_dinners d),
    'rotation',(select jsonb_agg(to_jsonb(d) order by id) from weekly_officer_rotation d),
    'audit_count',(select count(*) from audit_log))`);
  assert.deepEqual(afterFirstApply,beforeFirstApply);
  check(true,'first migration application preserves existing assignments, metadata and audit');
}
const actor = async id => { await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id ?? '']); await db.exec('set role authenticated'); };
async function denied(query,params=[],code='42501') {
  try { await db.query(query,params); assert.fail('Expected rejection'); }
  catch(e) { assert.equal(e.code,code); checks++; }
}
await actor(member);
const inserted=await scalar('select ensure_weekly_officer_schedule_v1($1,$2)',[club,year]);
check(inserted>=52 && inserted<=53,'calendar inserts only official Thursdays');
check(await scalar("select count(*)=0 from weekly_dinners where assigned_member_id is not null and extract(year from dinner_date)=$1",[year]),'member calendar generation leaves assignments empty');
check(await scalar("select bool_and(extract(dow from dinner_date)=4 and generated and assignment_source='auto') from weekly_dinners where extract(year from dinner_date)=$1",[year]),'calendar flags and weekday preserved');
const snapshot=await scalar('select jsonb_agg(to_jsonb(d) order by id) from weekly_dinners d');
check(await scalar('select ensure_weekly_officer_schedule_v1($1,$2)',[club,year])===0,'calendar repeat inserts zero');
assert.deepEqual(await scalar('select jsonb_agg(to_jsonb(d) order by id) from weekly_dinners d'),snapshot); checks++;
check(await scalar('select ensure_weekly_officer_schedule_v1($1,$2)',[club,year-2])===0,'past year does not fabricate history');
await denied('select ensure_weekly_officer_schedule_v1($1,null)',[club],'P0001');
await denied('select ensure_weekly_officer_schedule_v1($1,2101)',[club],'P0001');
await denied('select rebuild_weekly_officer_schedule_v1($1,$2)',[club,year]);
await denied('select rebuild_weekly_officer_schedule_internal_v1($1,current_date,current_date)',[club]);
for (const query of [
 'select reorder_weekly_officer_v1($1,array[]::uuid[])',
 'select set_weekly_officer_member_v1($1,$2,true,\'active\',false,null)',
 'select save_weekly_officer_absence_v1($1,null,$2,\'absence\',current_date,current_date,null)',
 'select delete_weekly_officer_absence_v1($1,$2)',
 'select save_weekly_dinner_v1($1,null,current_date,$2)',
 'select set_weekly_dinner_closed_v1($1,$2,true,null)'
]) await denied(query,query.includes('$2')?[club,a]:[club]);
await actor(outsider);
await denied('select ensure_weekly_officer_schedule_v1($1,$2)',[club,year]);
await denied('select rebuild_weekly_officer_schedule_v1($1,$2)',[club,year]);
await actor(null);
await denied('select ensure_weekly_officer_schedule_v1($1,$2)',[club,year]);
await denied('select rebuild_weekly_officer_schedule_v1($1,$2)',[club,year]);
await db.exec('reset role');
// Seed protected rows and history as the fixture owner, not via the public API.
await db.exec(`update weekly_dinners set assigned_member_id='${a}',assignment_source='manual' where dinner_date=(select min(dinner_date) from weekly_dinners);
update weekly_dinners set assigned_member_id='${a}',assignment_source='swap' where dinner_date=(select min(dinner_date)+7 from weekly_dinners);
update weekly_dinners set external_name='Fixture external',assignment_source='external' where dinner_date=(select min(dinner_date)+14 from weekly_dinners);
update weekly_dinners set assigned_member_id='${a}',status='completed' where dinner_date=(select min(dinner_date)+21 from weekly_dinners);
update weekly_dinners set status='closed' where dinner_date=(select min(dinner_date)+28 from weekly_dinners);
update weekly_dinners set status='cancelled' where dinner_date=(select min(dinner_date)+35 from weekly_dinners);
insert into weekly_dinners(club_id,dinner_date,dinner_kind,status,assigned_member_id) values
('${club}',current_date-7,'regular','planned','${a}'),('${club}',make_date(${year},1,2),'extraordinary','planned','${a}');`);
const protectedQuery="select jsonb_agg(to_jsonb(d) order by id) from weekly_dinners d where assignment_source<>'auto' or status<>'planned' or dinner_kind<>'regular' or dinner_date<current_date";
const protectedBefore=await scalar(protectedQuery);
await actor(manager);
let result=await scalar('select rebuild_weekly_officer_schedule_v1($1,$2)',[club,year]);
check(result.assigned===result.eligible && result.assigned>0,'manager explicitly assigns eligible dinners');
assert.deepEqual(await scalar(protectedQuery),protectedBefore); checks++;
check(await scalar('select ensure_weekly_officer_schedule_v1($1,$2)',[club,year])===0,'manager calendar load still does not rebuild');
const assignedSnapshot=await scalar('select jsonb_agg(to_jsonb(d) order by id) from weekly_dinners d');
await db.exec('reset role');
const auditBefore=Number(await scalar('select count(*) from audit_log'));
await db.exec(read('supabase/migrations/'+file));
assert.deepEqual(await scalar('select jsonb_agg(to_jsonb(d) order by id) from weekly_dinners d'),assignedSnapshot);
check(Number(await scalar('select count(*) from audit_log'))===auditBefore,'migration on populated schedule changes neither rows nor audit');
await actor(member);
await scalar('select ensure_weekly_officer_schedule_v1($1,$2)',[club,year]);
assert.deepEqual(await scalar('select jsonb_agg(to_jsonb(d) order by id) from weekly_dinners d'),assignedSnapshot);checks++;
if(catalogPath) {
  const query='select * from agenda_calendar_v1($1,make_date($2,1,1),make_date($2,12,31))';
  await denied(query,[club,year],'P0001');
  await db.exec('reset role');
  await db.query("insert into club_role_permissions(club_id,role_key,permission_key,allowed) values($1,'member','viewAgenda',true)",[club]);
  await db.query(`insert into agenda_items(club_id,item_type,title,starts_at,audience) values
    ($1,'meeting','Fixture public agenda',make_date($2,2,1)::timestamp at time zone 'Europe/Lisbon','all'),
    ($1,'meeting','Fixture direction agenda',make_date($2,2,1)::timestamp at time zone 'Europe/Lisbon','direction')`,[club,year]);
  await actor(member);
  const agendaBefore=await scalar('select jsonb_agg(to_jsonb(d) order by id) from weekly_dinners d');
  const agenda=(await db.query(query,[club,year])).rows;
  const expectedDinners=Number(await scalar('select count(*) from weekly_dinners where club_id=$1 and extract(year from dinner_date)=$2',[club,year]));
  check(agenda.filter(r=>r.source_type==='weekly_dinner').length===expectedDinners,'ordinary member reads real Agenda dinner RPC');
  check(agenda.some(r=>r.title==='Fixture public agenda') && !agenda.some(r=>r.title==='Fixture direction agenda'),'ordinary member Agenda preserves direction visibility guard');
  check(agenda.filter(r=>r.source_type==='weekly_dinner').every(r=>r.can_edit===false),'Agenda does not grant dinner management to member');
  assert.deepEqual(await scalar('select jsonb_agg(to_jsonb(d) order by id) from weekly_dinners d'),agendaBefore);
  check(true,'real Agenda RPC does not change dinner assignments or metadata');
  await denied(query,[other,year],'P0001');
  await actor(null);await denied(query,[club,year],'P0001');
}
await actor(manager);
await denied('select rebuild_weekly_officer_schedule_v1($1,$2)',[club,year-2],'22023');
await denied('select rebuild_weekly_officer_schedule_v1($1,null)',[club],'22023');
await denied('select reorder_weekly_officer_v1($1,$2::uuid[])',[club,[a,a]],'P0001');
// Move an absence later: the OLD affected Thursday must be recalculated too.
const date=await scalar("select dinner_date::text from weekly_dinners where assignment_source='auto' and status='planned' and dinner_date>make_date($1,2,1) order by dinner_date limit 1",[year]);
const absence=await scalar("select save_weekly_officer_absence_v1($1,null,$2,'absence',$3::date,$3::date,null)",[club,a,date]);
check(await scalar('select assigned_member_id from weekly_dinners where club_id=$1 and dinner_date=$2::date',[club,date])===b,'absence excludes member on affected date');
await db.exec('reset role');
await db.exec(`update weekly_officer_rotation set enabled=false where member_id='${b}';`);
await actor(manager);
await scalar("select save_weekly_officer_absence_v1($1,$2,$3,'absence',$4::date+28,$4::date+28,null)",[club,absence,a,date]);
check(await scalar('select assigned_member_id from weekly_dinners where club_id=$1 and dinner_date=$2::date',[club,date])===a,'moving absence later repairs OLD affected interval');
await scalar('select delete_weekly_officer_absence_v1($1,$2)',[club,absence]);
await db.exec('reset role');
await db.exec('update weekly_officer_rotation set enabled=false');
await actor(manager);
result=await scalar('select rebuild_weekly_officer_schedule_v1($1,$2)',[club,year]);
check(result.assigned===0,'no candidates leaves auto dinners unassigned');
await scalar("select set_weekly_officer_member_v1($1,$2,false,'inactive',true,null)",[club,a]);
result=await scalar('select rebuild_weekly_officer_schedule_v1($1,$2)',[club,year]);
check(result.assigned===result.eligible,'force inclusion behavior preserved');
for (const role of ['vice_president','super_admin']) {
 await db.exec('reset role'); await db.query('update club_memberships set access_role=$1 where profile_id=$2',[role,manager]);
 await actor(manager); check((await scalar('select rebuild_weekly_officer_schedule_v1($1,$2)',[club,year])).eligible>0,role+' membership can rebuild');
}
for (const role of ['secretary','treasurer','admin','member']) {
 await db.exec('reset role'); await db.query('update club_memberships set access_role=$1 where profile_id=$2',[role,manager]);
 await actor(manager); await denied('select rebuild_weekly_officer_schedule_v1($1,$2)',[club,year]);
}
await db.exec('reset role');
await db.query("update club_memberships set access_role='president',active=false where profile_id=$1",[manager]);
await actor(manager);await denied('select rebuild_weekly_officer_schedule_v1($1,$2)',[club,year]);
await db.exec('reset role');
check(await scalar("select not has_function_privilege('service_role','public.rebuild_weekly_officer_schedule_internal_v1(uuid,date,date)','execute')"),'service role cannot call internal rebuild directly');
check(await scalar("select not has_function_privilege('anon','public.ensure_weekly_officer_schedule_v1(uuid,integer)','execute')"),'anon cannot generate dates');
// Prove a failure rolls back calendar creation and attribution together.
await db.query('update club_memberships set active=true where profile_id=$1',[manager]);
await db.exec("create function fixture_fail_audit() returns trigger language plpgsql as $$ begin raise exception 'fixture failure'; end $$; create trigger fixture_fail before insert on audit_log for each row execute function fixture_fail_audit();");
await actor(manager);
await denied('select rebuild_weekly_officer_schedule_v1($1,$2)',[club,year+1],'P0001');
check(Number(await scalar('select count(*) from weekly_dinners where extract(year from dinner_date)=$1',[year+1]))===0,'audit failure rolls back generated dates and assignments');
if(native) {
  await db.exec('reset role; drop trigger fixture_fail on audit_log; update weekly_officer_rotation set enabled=true,force_included=false,availability_status=\'active\';');
  const worker=nativeConnect();
  try {
    await worker.unsafe("set statement_timeout='10s'; set lock_timeout='8s';");
    const [{pid}] = await worker.unsafe('select pg_backend_pid() pid');
    await worker.unsafe("select set_config('request.jwt.claim.sub',$1,false)",[manager]);
    await worker.unsafe('set role authenticated');
    const contenders=[
      ['explicit rebuild','select rebuild_weekly_officer_schedule_v1($1,$2)',[club,year]],
      ['rotation reorder','select reorder_weekly_officer_v1($1,$2::uuid[])',[club,[b,a]]],
      ['calendar ensure','select ensure_weekly_officer_schedule_v1($1,$2)',[club,year]],
      ['absence insert',"select save_weekly_officer_absence_v1($1,null,$2,'absence',$3::date,$3::date,null)",[club,a,date]],
      ['absence delete',"select delete_weekly_officer_absence_v1($1,(select id from weekly_officer_absences where club_id=$1 and member_id=$2 and starts_on=$3::date limit 1))",[club,a,date]],
      ['absence restore',"select save_weekly_officer_absence_v1($1,null,$2,'absence',$3::date,$3::date,null)",[club,a,date]],
      ['dinner manual edit',"select save_weekly_dinner_v1($1,(select id from weekly_dinners where club_id=$1 and dinner_date=$2::date),$2::date,$3)",[club,date,b]],
      ['dinner close',"select set_weekly_dinner_closed_v1($1,(select id from weekly_dinners where club_id=$1 and dinner_date=$2::date),true,null)",[club,date]],
      ['dinner reopen',"select set_weekly_dinner_closed_v1($1,(select id from weekly_dinners where club_id=$1 and dinner_date=$2::date),false,null)",[club,date]],
    ];
    for(const [name,sql,params] of contenders) {
      await actor(manager);
      await db.exec('begin');
      await scalar('select rebuild_weekly_officer_schedule_v1($1,$2)',[club,year]);
      await db.exec('reset role');
      let settled=false;
      const pending=worker.unsafe(sql,params).then(rows=>{settled=true;return {rows};},error=>{settled=true;return {error};});
      let waiting=false;
      for(let i=0;i<100 && !settled;i++) {
        waiting=await scalar("select exists(select 1 from pg_locks where pid=$1 and locktype='advisory' and not granted)",[pid]);
        if(waiting) break;
        await db.exec('select pg_sleep(0.02)');
      }
      await db.exec('commit');
      const result=await pending;
      assert.ifError(result.error);
      check(waiting, name+' waits for concurrent rebuild lock and completes after commit');
    }
    // Insertion by the owner follows the real member append trigger and must also wait.
    await worker.unsafe('reset role');
    await actor(manager);await db.exec('begin');
    await scalar('select rebuild_weekly_officer_schedule_v1($1,$2)',[club,year]);
    await db.exec('reset role');
    const newMember='20000000-0000-0000-0000-000000000003';
    const insertPending=worker.unsafe("insert into members(id,club_id,full_name,status) values($1,$2,'C','active')",[newMember,club]).then(rows=>({rows}),error=>({error}));
    let waiting=false;
    for(let i=0;i<100;i++) {
      waiting=await scalar("select exists(select 1 from pg_locks where pid=$1 and locktype='advisory' and not granted)",[pid]);
      if(waiting) break;await db.exec('select pg_sleep(0.02)');
    }
    await db.exec('commit');assert.ifError((await insertPending).error);
    check(waiting,'member append waits for concurrent rebuild');
    check(Number(await scalar('select count(*) from weekly_officer_rotation where club_id=$1 and member_id=$2',[club,newMember]))===1,'concurrent append produces exactly one rotation member');
    // Separate clubs must remain independent while the first club's transaction is open.
    await db.query("insert into club_memberships(club_id,profile_id,active,access_role) values($1,$2,true,'president')",[other,manager]);
    await actor(manager);await db.exec('begin');
    await scalar('select rebuild_weekly_officer_schedule_v1($1,$2)',[club,year]);
    await worker.unsafe('set role authenticated');
    const independent=await worker.unsafe('select rebuild_weekly_officer_schedule_v1($1,$2)',[other,year]);
    check(independent.length===1,'different club rebuild completes while first club is locked');
    await db.exec('rollback');
    // Validate the serial final state after the operations above.
    await db.exec('reset role');
    check(await scalar("select bool_and(not (d.assigned_member_id=$2 and d.dinner_date=$3::date)) from weekly_dinners d where d.club_id=$1 and d.status='planned' and d.assignment_source='auto'",[club,a,date]),'final assignments respect concurrent absence');
    check(Number(await scalar("select count(*) from weekly_officer_rotation where club_id=$1",[club]))===3,'rotation retains reorder and concurrent append');
    check(await scalar("select exists(select 1 from audit_log where entity_type='weekly_dinners' and action='updated')"),'real audit trigger captures schedule writes');
  } finally {
    await db.exec('rollback; reset role');
    await worker.end({timeout:5});
  }
}
if(native) {
 await db.exec('reset role');
 writeFileSync(resolve(root,catalogPath?'docs/PHASE_2C2_CATALOG_RESULTS.json':'docs/PHASE_2C2_NATIVE_MODULE_RESULTS.json'),JSON.stringify({
  engine:await scalar('select version()'),endpoint:'127.0.0.1:55439',checks,
  mode:catalogPath?'Native restored schema metadata, synthetic data and local auth/net/storage adapters':'Native module fixture with versioned audit triggers; full historical replay did not pass',
  restoredCatalog,
  passedChecks:messages,denialAndSnapshotAssertions:checks-messages.length,
 },null,2));
}
await db.close();
console.log(`SQL assertions passed: ${checks}. Mode: ${native?'native PostgreSQL with real audit triggers':'PGlite'}.`);
