// Exact policy predicate comparison on isolated relations. No public DDL persists.
import {readFileSync,writeFileSync} from 'node:fs';import {resolve} from 'node:path';import {pathToFileURL} from 'node:url';import assert from 'node:assert/strict';
const pg=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const {database}=JSON.parse(readFileSync('docs/PHASE_BASELINE_REBUILD_RESULTS.json'));assert.match(database,/^bob_clean_rebuild_\d+$/);
const items=JSON.parse(readFileSync('docs/PHASE_GROUPED_DRIFT_CLASSIFICATION.json')).items.filter(x=>x.outcome==='pending'&&x.kind==='policy'&&x.table.startsWith('event_'));assert.equal(items.length,6);
const prod=JSON.parse(readFileSync('docs/PHASE_STRUCTURAL_PRODUCTION_SNAPSHOT.json'));
const statuses=prod.enums.find(x=>x.name==='event_status').values;
const sql=pg({host:'127.0.0.1',port:55440,user:'postgres',database,max:1,prepare:false,onnotice:()=>{}});
const c='00000000-0000-0000-0000-000000000001',u='00000000-0000-0000-0000-000000000010',other='00000000-0000-0000-0000-000000000011';
const results=[];const commands={a:'insert',w:'update',d:'delete'};
try{await sql.unsafe('begin');await sql.unsafe(`insert into auth.users(id,email) values('${u}','event-policy@example.invalid'),('${other}','event-other@example.invalid');insert into public.clubs(id,name,slug) values('${c}','Event policy','event-policy');insert into public.club_memberships(club_id,profile_id,access_role,active) values('${c}','${u}','member',true);select set_config('request.jwt.claim.sub','${u}',true);insert into public.user_permission_overrides(club_id,profile_id,permission_key,allowed) values('${c}','${u}','manageEventParticipants',false);`);
for(const item of items){
 // The only syntactic delta must be the cast of the two literal status labels.
 const norm=p=>JSON.stringify(p).replaceAll('::event_status','::text');assert.equal(norm(item.production),norm(item.rebuild));
 const cases=[];
 for(const source of ['production','rebuild']){
  const schema='event_policy_'+source;await sql.unsafe(`create schema ${schema};grant usage on schema ${schema} to authenticated;set local search_path=${schema},public;
  ${source==='production'?`create type event_status as enum (${statuses.map(s=>"'"+s.replaceAll("'","''")+"'").join(',')});`:''}
  create table events(id int,club_id uuid,status ${source==='production'?'event_status':'text'});create table members(id int,club_id uuid,profile_id uuid);create table event_registrations(id int,event_id int,member_id int);create table event_registration_guests(id int,registration_id int);
  insert into events values(1,'${c}','published');insert into members values(1,'${c}','${u}');insert into event_registrations values(1,1,1);insert into event_registration_guests values(1,1);
  grant select,insert,update,delete on all tables in schema ${schema} to authenticated;
  alter table ${item.table} enable row level security;create policy readable on ${item.table} for select to authenticated using(true);`);
  const p=item[source],cmd=commands[p.command];assert.ok(cmd);
  await sql.unsafe(`create policy tested on ${item.table} for ${cmd} to authenticated ${p.using?'using('+p.using+')':''} ${p.check?'with check('+p.check+')':''}`);
  for(const status of [...statuses,null])for(const own of [true,false])for(const tenant of [true,false])for(const active of [true,false])for(const permission of [true,false]){
   await sql.unsafe(`update public.club_memberships set active=true where club_id='${c}' and profile_id='${u}'`);
   await sql.unsafe('update events set status=$1',[status]);await sql.unsafe('update members set profile_id=$1,club_id=$2',[own?u:other,tenant?c:null]);await sql.unsafe('update public.user_permission_overrides set allowed=$1 where club_id=$2 and profile_id=$3',[permission,c,u]);await sql.unsafe('update public.club_memberships set active=$1 where club_id=$2 and profile_id=$3',[active,c,u]);
   await sql.unsafe('savepoint operation');await sql.unsafe('set local role authenticated');let outcome;
   try{const t=item.table;const query=cmd==='insert'?(t==='event_registrations'?`insert into ${t} values(2,1,1) returning id`:`insert into ${t} values(2,1) returning id`):cmd==='update'?`update ${t} set id=2 where id=1 returning id`:`delete from ${t} where id=1 returning id`;
    const rows=await sql.unsafe(query);outcome={rows:rows.length};}catch(e){assert.equal(e.code,'42501');outcome={rows:0,code:e.code};}
   await sql.unsafe('rollback to savepoint operation');cases.push({source,status,own,tenant,active,permission,...outcome});
  }
  await sql.unsafe(`set local search_path=public;drop schema ${schema} cascade`);
 }
 const a=cases.filter(x=>x.source==='production').map(({source,...x})=>x),b=cases.filter(x=>x.source==='rebuild').map(({source,...x})=>x);assert.deepEqual(a,b);assert.ok(a.some(x=>x.rows===1));assert.ok(a.some(x=>x.rows===0));
 results.push({id:item.id,classification:'equivalent',cases_per_catalog:a.length,allowed:a.filter(x=>x.rows===1).length,denied:a.filter(x=>!x.rows).length,cases});
}
}finally{await sql.unsafe('rollback').catch(()=>{});await sql.end();}
writeFileSync('docs/PHASE_FINAL_EVENT_POLICIES.json',JSON.stringify({database,scope:'Isolated exact predicates, real RBAC; SELECT support policy deliberate; not integrated event writers, grants or domain-type equivalence',results},null,2)+'\n');console.log(JSON.stringify(results.map(({cases,...x})=>x)));
