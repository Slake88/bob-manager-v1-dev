// Fixed disposable loopback only. Real tables/helpers/triggers; all changes roll back.
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';import {pathToFileURL} from 'node:url';import assert from 'node:assert/strict';
const pg=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const before=process.argv.includes('--before');
const {database}=JSON.parse(readFileSync('docs/PHASE_BASELINE_REBUILD_RESULTS.json'));assert.match(database,/^bob_clean_rebuild_\d+$/);
const sql=pg({host:'127.0.0.1',port:55440,user:'postgres',database,max:1,prepare:false,onnotice:()=>{}});
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
const c=id(1),u=id(10),other=id(11),outsider=id(12),d=id(40),row=id(50);
const result={database,before,scope:'Real public tables and RBAC, explicit test grants; PostgreSQL adapters, no production ACL/Auth/Storage claims',results:[]};
const ops=['SELECT','INSERT','UPDATE','DELETE'];
const hasLabel=(await sql.unsafe("select exists(select 1 from information_schema.columns where table_schema='public' and table_name='document_versions' and column_name='version_label') yes"))[0].yes;
async function probe(table,op,insert,update){
 await sql.unsafe('savepoint probe');let r;
 try {const q=op==='SELECT'?`select id from public.${table} where id='${row}'`:op==='DELETE'?`delete from public.${table} where id='${row}' returning id`:op==='UPDATE'?`update public.${table} set ${update} where id='${row}' returning id`:insert;
 r={rows:(await sql.unsafe(q)).length};}catch(e){r={rows:0,code:e.code,message:e.message};}
 await sql.unsafe('rollback to savepoint probe');return r;
}
const statements={
 document_links:{insert:`insert into public.document_links(id,club_id,document_id,linked_entity_type) values('${id(51)}','${c}','${d}','member') returning id`,update:"linked_entity_type='event'"},
 document_versions:{insert:`insert into public.document_versions(id,club_id,document_id,version_no,storage_path,created_by,is_current${hasLabel?',version_label':''}) values('${id(51)}','${c}','${d}',2,'probe/second',auth.uid(),false${hasLabel?",'2.0'":''}) returning id`,update:"change_notes='updated'"},
 notifications:{insert:`insert into public.notifications(id,club_id,profile_id,title,body) values('${id(51)}','${c}','${other}','Injected','Injected') returning id`,update:"read_at=now()"},
 euromillions_draws:{insert:`insert into public.euromillions_draws(id,club_id,week,start_date,end_date) values('${id(51)}','${c}',2,'2026-10-19','2026-10-25') returning id`,update:'prize=99'}
};
async function matrix(table){const r={};for(const op of ops)r[op]=await probe(table,op,statements[table].insert,statements[table].update);return r;}
async function actor(user,role='authenticated'){await sql.unsafe(`reset role;select set_config('request.jwt.claim.sub','${user??(role==='postgres'?u:'')}',true);set local role ${role}`);}
try {
 await sql.unsafe('begin');
 await sql.unsafe(`insert into auth.users(id,email) values('${u}','policy-member@example.invalid'),('${other}','policy-owner@example.invalid'),('${outsider}','policy-outsider@example.invalid');insert into public.clubs(id,name,slug) values('${c}','Final policies','final-policies');insert into public.club_memberships(club_id,profile_id,access_role,active) values('${c}','${u}','member',true),('${c}','${other}','member',true);
 insert into public.notification_preferences(club_id,profile_id,module_code,in_app_enabled,push_enabled) values('${c}','${u}','documents',false,false),('${c}','${other}','documents',false,false);
 select set_config('request.jwt.claim.sub','${other}',true);
 insert into public.documents(id,club_id,name,scope,owner_profile_id,sensitive) values('${d}','${c}','Private document','personal','${other}',false);
 insert into public.document_links(id,club_id,document_id,linked_entity_type) values('${row}','${c}','${d}','member');
 insert into public.document_versions(id,club_id,document_id,version_no,storage_path,created_by${hasLabel?',version_label':''}) values('${row}','${c}','${d}',1,'probe/first','${other}'${hasLabel?",'1.0'":''});
 insert into public.notifications(id,club_id,profile_id,title,body) values('${row}','${c}','${other}','Private notification','Private body');
 insert into public.euromillions_draws(id,club_id,week,start_date,end_date) values('${row}','${c}',1,'2026-10-12','2026-10-18');
 grant select,insert,update,delete on public.document_links,public.document_versions,public.notifications,public.euromillions_draws to authenticated,anon;
 grant select on public.documents to authenticated;
 insert into public.user_permission_overrides(club_id,profile_id,permission_key,allowed) values('${c}','${u}','manageDocuments',false),('${c}','${u}','viewDocuments',false),('${c}','${u}','manageLottery',false);`);
 for(const table of ['document_links','document_versions','notifications']){
  const name=table+'_tenant';await actor(u);const actual=await matrix(table);await actor(null,'postgres');
  await sql.unsafe(`drop policy if exists ${name} on public.${table}`);
  await actor(u);const repaired=await matrix(table);
  assert.ok(ops.every(op=>repaired[op].rows===0&&(!repaired[op].code||repaired[op].code==='42501'||(table==='document_versions'&&op==='INSERT'&&repaired[op].code==='P0001'))),table+' denied non-owner '+JSON.stringify(repaired));
  if(before)assert.ok(ops.filter(op=>table!=='document_versions'||op!=='INSERT').every(op=>actual[op].rows===1),table+' reproduce bypass');else assert.deepEqual(actual,repaired);
  await actor(other);const owner=await matrix(table);
  if(table==='notifications'){assert.equal(owner.SELECT.rows,1);assert.equal(owner.UPDATE.rows,1);assert.equal(owner.INSERT.code,'42501');assert.equal(owner.DELETE.rows,0);}
  else assert.ok(ops.every(op=>owner[op].rows===1),table+' owner CRUD '+JSON.stringify(owner));
  await actor(null,'postgres');
  if(table!=='notifications')await sql.unsafe(`update public.user_permission_overrides set allowed=true where club_id='${c}' and profile_id='${u}' and permission_key='manageDocuments'`);
  await actor(u);const manager=await matrix(table);
  if(table!=='notifications')assert.ok(ops.every(op=>manager[op].rows===1),table+' manager CRUD');
  await actor(outsider);const outside=await matrix(table);assert.ok(ops.every(op=>outside[op].rows===0));
  await actor(null,'anon');const anon=await matrix(table);assert.ok(ops.every(op=>anon[op].rows===0));
  await actor(null,'postgres');await sql.unsafe(`update public.user_permission_overrides set allowed=false where club_id='${c}' and profile_id='${u}'`);
  result.results.push({table,actual,repaired,owner,manager,outsider:outside,anon});
 }
 // Compare the captured permissive production policy with the permission policy.
 await sql.unsafe(`create policy captured_access_control on public.euromillions_draws for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))`);
 await actor(u);const unsafe=await matrix('euromillions_draws');assert.ok(ops.every(op=>unsafe[op].rows===1));
 await actor(null,'postgres');await sql.unsafe('drop policy captured_access_control on public.euromillions_draws');
 await actor(u);const actual=await matrix('euromillions_draws');
 if(before)assert.equal(actual.SELECT.rows,0);else assert.equal(actual.SELECT.rows,1);
 assert.equal(actual.INSERT.code,'42501');assert.equal(actual.UPDATE.rows,0);assert.equal(actual.DELETE.rows,0);
 await actor(null,'postgres');
 if(before)await sql.unsafe('create policy euromillions_read on public.euromillions_draws for select to authenticated using(public.has_club_access(club_id))');
 await actor(u);const repaired=await matrix('euromillions_draws');assert.equal(repaired.SELECT.rows,1);assert.equal(repaired.INSERT.code,'42501');assert.equal(repaired.UPDATE.rows,0);assert.equal(repaired.DELETE.rows,0);
 await actor(null,'postgres');await sql.unsafe(`update public.user_permission_overrides set allowed=true where club_id='${c}' and profile_id='${u}' and permission_key='manageLottery'`);
 await actor(u);const manager=await matrix('euromillions_draws');assert.ok(ops.every(op=>manager[op].rows===1));
 await actor(outsider);const outside=await matrix('euromillions_draws');assert.ok(ops.every(op=>outside[op].rows===0));
 await actor(null,'anon');const anon=await matrix('euromillions_draws');assert.ok(ops.every(op=>anon[op].rows===0));
 result.results.push({table:'euromillions_draws',captured_unsafe:unsafe,actual,repaired,manager,outsider:outside,anon});result.status='passed';
} finally {await sql.unsafe('rollback').catch(()=>{});await sql.end();writeFileSync('docs/PHASE_FINAL_POLICIES_'+(before?'BEFORE':'AFTER')+'.json',JSON.stringify(result,null,2)+'\n');}
console.log(JSON.stringify({status:result.status,tables:result.results.length}));
