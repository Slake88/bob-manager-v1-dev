// Real document tables and helpers, fixed loopback only, transaction rollback.
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const root=resolve(import.meta.dirname,'..');
const postgres=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const replay=JSON.parse(readFileSync(resolve(root,'docs/PHASE_BASELINE_REBUILD_RESULTS.json'),'utf8'));
assert.match(replay.database,/^bob_clean_rebuild_\d+$/);
const sql=postgres({host:'127.0.0.1',port:55440,user:'postgres',database:replay.database,max:1,prepare:false,onnotice:()=>{}});
const c='00000000-0000-0000-0000-000000000001',u='00000000-0000-0000-0000-000000000010',other='00000000-0000-0000-0000-000000000011',d='00000000-0000-0000-0000-000000000040';
const tables=['document_access_log','document_approvals','document_ocr'],ops=['SELECT','INSERT','UPDATE','DELETE'];
const keys=['viewDocuments','manageDocuments','approveDocuments','runDocumentOcr'];
const results=[];
try{
 await sql.unsafe('begin');
 await sql.unsafe(`insert into auth.users(id,email) values('${u}','document-rls@example.invalid'),('${other}','other@example.invalid');
 insert into public.clubs(id,name,slug) values('${c}','Document fixture','document-rls');
 insert into public.club_memberships(id,club_id,profile_id,access_role,active) values('00000000-0000-0000-0000-000000000020','${c}','${u}','member',true);
 select set_config('request.jwt.claim.sub','${u}',true);
 insert into public.notification_preferences(club_id,profile_id,module_code,in_app_enabled,push_enabled) values('${c}','${u}','documents',false,false);
 insert into public.documents(id,club_id,name,scope,sensitive) values('${d}','${c}','Protected document','club',false);
 insert into public.documents(id,club_id,name,scope,sensitive) values('00000000-0000-0000-0000-000000000041','${c}','Insert document','club',false);
 grant select on public.documents to authenticated;
 grant select,insert,update,delete on public.document_access_log,public.document_approvals,public.document_ocr to authenticated,anon;
 insert into public.document_access_log(id,club_id,document_id,profile_id,action) values('00000000-0000-0000-0000-000000000070','${c}','${d}','${other}','view');
 insert into public.document_approvals(id,club_id,document_id,requested_by,status) values('${d}','${c}','${d}','${other}','pending');
 insert into public.document_ocr(id,club_id,document_id,status) values('${d}','${c}','${d}','pending');`);
 async function probe(t,op){
  await sql.unsafe('savepoint operation');let r;
  const id=t==='document_access_log'?"'00000000-0000-0000-0000-000000000070'":`'${d}'`;
  try{
   if(op==='SELECT')r={rows:(await sql.unsafe(`select id from public.${t} where id=${id}`)).length};
   if(op==='UPDATE')r={rows:(await sql.unsafe(`update public.${t} set ${t==='document_access_log'?"action='download'":"status='pending'"} where id=${id} returning id`)).length};
   if(op==='DELETE')r={rows:(await sql.unsafe(`delete from public.${t} where id=${id} returning id`)).length};
   if(op==='INSERT'){
    const statements={document_access_log:`insert into public.document_access_log(id,club_id,document_id,profile_id,action) values('00000000-0000-0000-0000-000000000071','${c}','${d}','${u}','view') returning id`,document_approvals:`insert into public.document_approvals(club_id,document_id,requested_by,status) values('${c}','${d}','${u}','pending') returning id`,document_ocr:`insert into public.document_ocr(club_id,document_id,status) values('${c}','${d}','pending') returning id`};
    const statement=t==='document_approvals'||t==='document_ocr'?statements[t].replace(`'${d}'`,"'00000000-0000-0000-0000-000000000041'"):statements[t];
    r={rows:(await sql.unsafe(statement)).length};
   }
  }catch(e){r={rows:0,code:e.code,message:e.message};}
  await sql.unsafe('rollback to savepoint operation');return r;
 }
 for(const t of tables){
  await sql.unsafe(`delete from public.user_permission_overrides where club_id='${c}' and profile_id='${u}'; update public.club_memberships set access_role='member' where profile_id='${u}'`);
  await sql.unsafe(`drop policy if exists ${t}_tenant on public.${t}; create policy ${t}_tenant on public.${t} for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))`);
  await sql.unsafe('set local role authenticated');const before={};for(const op of ops)before[op]=await probe(t,op);await sql.unsafe('reset role');
  await sql.unsafe(`drop policy ${t}_tenant on public.${t}`);
  await sql.unsafe('set local role authenticated');const after={};for(const op of ops)after[op]=await probe(t,op);await sql.unsafe('reset role');
  assert.ok(ops.every(op=>before[op].rows===1),t+' control '+JSON.stringify(before));assert.ok(ops.every(op=>after[op].rows===0),t+' denial '+JSON.stringify(after));
  await sql.unsafe(`insert into public.user_permission_overrides(club_id,profile_id,permission_key,allowed) select $1::uuid,$2::uuid,k,true from unnest($3::text[]) k`,[c,u,keys]);
  await sql.unsafe('set local role authenticated');const authorized={};for(const op of ops)authorized[op]=await probe(t,op);await sql.unsafe('reset role');
  assert.equal(authorized.SELECT.rows,1);assert.equal(authorized.INSERT.rows,1);
  if(t==='document_ocr'){assert.equal(authorized.UPDATE.rows,1);assert.equal(authorized.DELETE.rows,1);}
  if(t==='document_access_log'){assert.equal(authorized.UPDATE.rows,0);assert.equal(authorized.DELETE.rows,0);}
  await sql.unsafe(`delete from public.user_permission_overrides where club_id='${c}' and profile_id='${u}'`);
  await sql.unsafe(`insert into public.club_role_permissions(club_id,role_key,permission_key,allowed) select $1::uuid,'admin',k,true from unnest($2::text[]) k on conflict(club_id,role_key,permission_key) do update set allowed=true`,[c,keys]);
  const privileged={};for(const role of ['admin','super_admin']){
   await sql.unsafe(`update public.club_memberships set access_role=$1 where profile_id=$2`,[role,u]);await sql.unsafe('set local role authenticated');const state={};for(const op of ops)state[op]=await probe(t,op);await sql.unsafe('reset role');assert.deepEqual(state,authorized,t+' '+role);privileged[role]=state;
  }
  await sql.unsafe(`select set_config('request.jwt.claim.sub','',true)`);await sql.unsafe('set local role anon');const anon={};for(const op of ops)anon[op]=await probe(t,op);await sql.unsafe('reset role');assert.ok(ops.every(op=>anon[op].rows===0));
  await sql.unsafe(`select set_config('request.jwt.claim.sub','${u}',true)`);
  results.push({table:t,policy:t+'_tenant',status:'passed',before,after,authorized,privileged,anon,scope:'Real document tables, RLS, invoker helper, audit triggers; notifications preference opted out'});console.log(t+' passed');
 }
}finally{await sql.unsafe('rollback').catch(()=>{});await sql.end();}
writeFileSync(resolve(root,'docs/PHASE_POLICY_DOCUMENTS_SQL_RESULTS.json'),JSON.stringify({database:replay.database,results},null,2)+'\n');
