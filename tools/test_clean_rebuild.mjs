// Empty disposable PostgreSQL database; fixed loopback, no remote configuration.
// node tools/test_clean_rebuild.mjs <postgres.js/src/index.js>
import {readFileSync,writeFileSync,readdirSync,existsSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
const root=resolve(import.meta.dirname,'..');
const postgres=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const options={host:'127.0.0.1',port:55440,user:'postgres',max:1,prepare:false,onnotice:()=>{}};
const database='bob_clean_rebuild_'+Date.now();
const allowExtensionAdapters=process.argv.includes('--allow-extension-adapters');
const originalBaseline=process.argv.includes('--original-baseline');
const report={database,endpoint:'127.0.0.1:55440',started_at:new Date().toISOString(),adapter_limit:'SQL only; Auth/Storage/net/cron adapters; no Supabase service integration',allow_extension_adapters:allowExtensionAdapters,original_baseline:originalBaseline,extension_substitutions:[],applied:[]};
const admin=postgres({...options,database:'postgres'});
await admin.unsafe(`create database ${database}`);await admin.end();
const sql=postgres({...options,database});
try {
 await sql.unsafe(`
 do $$ begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
 end $$;
 create schema auth; create schema storage; create schema net; create schema extensions; create schema cron;
 create table cron.local_jobs(id bigserial primary key,name text,schedule text,command text);
 create function cron.schedule(job_name text,schedule text,command text) returns bigint language plpgsql as $$declare result bigint;begin insert into cron.local_jobs(name,schedule,command) values(job_name,schedule,command) returning id into result;return result;end$$;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}');
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.role() returns text language sql stable as $$select nullif(current_setting('request.jwt.claim.role',true),'')$$;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create table storage.buckets(id text primary key,name text,public boolean default false,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,owner uuid,owner_id text,metadata jsonb);
 alter table storage.objects enable row level security;
 create function storage.foldername(name text) returns text[] language sql immutable as $$select (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1]$$;
 create table net.local_http_capture(id bigserial primary key,url text,body jsonb,headers jsonb);
 create function net.http_post(url text,body jsonb default '{}',params jsonb default '{}',headers jsonb default '{}',timeout_milliseconds integer default 5000) returns bigint language plpgsql as $$declare result bigint;begin insert into net.local_http_capture(url,body,headers) values(url,body,headers) returning id into result;return result;end$$;
 grant usage on schema auth,storage to anon,authenticated,service_role;
 grant select,insert,update,delete on storage.objects to authenticated;
 create extension unaccent with schema extensions;
 -- Platform default function ACL for postgres/public captured in the production snapshot.
 alter default privileges for role postgres revoke execute on functions from public;
 alter default privileges for role postgres in schema public grant execute on functions to anon,authenticated,service_role;
 `);
 report.pre_migration_public_tables=Number((await sql.unsafe(`select count(*) n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'`))[0].n);
 const files=readdirSync(resolve(root,'supabase/migrations')).filter(f=>f.endsWith('.sql')).sort();
 report.total=files.length;
 for(const file of files) {
  const body=originalBaseline&&file.startsWith('1000_')?execFileSync('git',['show','HEAD:supabase/migrations/'+file],{cwd:root,encoding:'utf8'}):readFileSync(resolve(root,'supabase/migrations',file),'utf8');
  let executable=body;
  if(allowExtensionAdapters) executable=body.replace(/^create extension if not exists (pg_net with schema extensions|pg_cron);\r?$/gm,(statement)=>{report.extension_substitutions.push({file,statement,reason:'Native Windows PostgreSQL has no extension binary; explicit local adapter only'});return '-- '+statement.trim()+' [explicit test adapter]';});
  try {await sql.unsafe(executable);report.applied.push({file,sha256:createHash('sha256').update(body).digest('hex')});}
  catch(e) {report.first_failure={file,code:e.code,message:e.message,position:e.position,detail:e.detail,where:e.where};throw e;}
 }
 report.checks=[];
 const snapshot=JSON.parse(readFileSync(resolve(root,'docs/PHASE_RECONCILIATION_PRODUCTION_SNAPSHOT.json'),'utf8')).snapshot;
 const hash=s=>createHash('md5').update(s.replaceAll('\r\n','\n')).digest('hex');
 for(const name of ['handle_new_user','has_club_role','has_club_access','member_status_timeline_trigger_v1']) {
  const f=snapshot.functions.find(f=>f.name===name);
  const actual=(await sql.unsafe(`select p.prosrc,p.prosecdef,p.provolatile,p.proisstrict,p.proparallel,p.proconfig,pg_get_userbyid(p.proowner) owner,pg_get_function_arguments(p.oid) arguments,pg_get_function_result(p.oid) result from pg_proc p where p.oid=to_regprocedure($1)`,['public.'+f.signature]))[0];
  assert.ok(actual,name+' exists');
  assert.equal(hash(actual.prosrc),hash(f.definition.match(/\bas\s+(\$\w*\$)([\s\S]*?)\1/i)[2]));
  for(const [key,value] of Object.entries({prosecdef:true,provolatile:f.volatility,proisstrict:false,proparallel:'u',owner:'postgres',arguments:f.arguments,result:f.result})) assert.equal(actual[key],value,name+'.'+key);
  assert.deepEqual(actual.proconfig,f.config);
  for(const role of ['anon','authenticated','service_role']) assert.equal((await sql.unsafe('select has_function_privilege($1,$2,\'EXECUTE\') allowed',[role,'public.'+f.signature]))[0].allowed,f.effective_execute[role],name+' ACL '+role);
 }
 report.checks.push('Four active function bodies/signatures/attributes/owners/effective role ACLs match captured production');
 const identity=await sql.unsafe(`select c.relname,a.attname,format_type(a.atttypid,a.atttypmod) type,a.attnotnull from pg_attribute a join pg_class c on c.oid=a.attrelid where (a.attrelid='public.profiles'::regclass and a.attname='email') or (a.attrelid='public.clubs'::regclass and a.attname='slug')`);
 assert.equal(identity.length,2);for(const c of identity){assert.equal(c.type,'text');assert.equal(c.attnotnull,true);}
 assert.equal((await sql.unsafe(`select pg_get_constraintdef(oid) def from pg_constraint where conrelid='public.clubs'::regclass and conname='clubs_slug_key'`))[0].def,'UNIQUE (slug)');
 assert.equal((await sql.unsafe(`select pg_get_indexdef('public.clubs_slug_unique_idx'::regclass) def`))[0].def,snapshot.table_indexes.find(i=>i.indexname==='clubs_slug_unique_idx').indexdef);
 for(const name of ['alerts_v1','dashboard_summary_v1','member_milestones','protect_profile_privileges','is_administrator','is_finance_manager','has_permission']) assert.equal((await sql.unsafe('select count(*) n from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname=\'public\' and p.proname=$1',[name]))[0].n,'0');
 report.checks.push('Identity text/NOT NULL; both production slug uniqueness objects; seven omitted legacy functions absent');
 const prerequisites=JSON.parse(readFileSync(resolve(root,'docs/PHASE_BASELINE_MISSING_OBJECTS_SNAPSHOT.json'),'utf8')).relations.filter(t=>t.name!=='euromillions_draw_charges');
 for(const t of prerequisites)for(const k of t.constraints) {
  const actual=(await sql.unsafe(`select pg_get_constraintdef(oid) definition,convalidated from pg_constraint where conrelid=to_regclass($1) and conname=$2`,['public.'+t.name,k.name]))[0];
  assert.ok(actual,t.name+'.'+k.name);assert.equal(actual.definition,k.definition);assert.equal(actual.convalidated,true);
 }
 report.checks.push('All captured constraints/FKs of ten missing prerequisite tables match final reconstructed catalog');
 const denied=async(statement,code)=>{await sql.unsafe('savepoint rejected');let failure;try{await sql.unsafe(statement);}catch(e){failure=e;}await sql.unsafe('rollback to savepoint rejected');assert.equal(failure?.code,code,statement);};
 await sql.unsafe('begin');
 await sql.unsafe(`insert into auth.users(id,email,raw_user_meta_data) values('00000000-0000-0000-0000-000000000010','fixture@example.invalid','{"full_name":"Synthetic"}');`);
 assert.equal((await sql.unsafe(`select full_name from public.profiles where id='00000000-0000-0000-0000-000000000010'`))[0].full_name,'Synthetic');
 await sql.unsafe(`insert into auth.users(id,email) values('00000000-0000-0000-0000-000000000011','fallback@example.invalid')`);
 assert.equal((await sql.unsafe(`select full_name from public.profiles where id='00000000-0000-0000-0000-000000000011'`))[0].full_name,'fallback');
 await denied(`insert into auth.users(id,email) values('00000000-0000-0000-0000-000000000012',null)`,'23502');
 await sql.unsafe(`insert into public.clubs(id,name,slug) values('00000000-0000-0000-0000-000000000001','Synthetic','fixture');insert into public.club_memberships(id,club_id,profile_id,access_role,active) values('00000000-0000-0000-0000-000000000020','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000010','member',true);`);
 await denied(`insert into public.clubs(name,slug) values('Duplicate','fixture')`,'23505');
 await denied(`insert into public.clubs(name) values('Null slug')`,'23502');
 const call=async(club='00000000-0000-0000-0000-000000000001',uid='00000000-0000-0000-0000-000000000010')=>{await sql.unsafe(`select set_config('request.jwt.claim.sub',$1,true)`,[uid]);await sql.unsafe('set local role authenticated');const r=(await sql.unsafe(`select public.has_club_access($1::uuid) access,public.has_club_role($1::uuid,array['member']) member,public.has_club_role($1::uuid,array['super_admin']) admin`,[club]))[0];await sql.unsafe('reset role');return r;};
 assert.deepEqual({...await call()},{access:true,member:true,admin:false});
 await sql.unsafe('set local role authenticated');
 assert.equal((await sql.unsafe(`select public.has_club_permission('00000000-0000-0000-0000-000000000001','viewMembers') allowed`))[0].allowed,false);
 await sql.unsafe('reset role');
 await sql.unsafe(`insert into public.membership_roles(club_membership_id) values('00000000-0000-0000-0000-000000000020')`);
 await sql.unsafe('set local role authenticated');
 assert.equal((await sql.unsafe('select count(*) n from public.membership_roles'))[0].n,'1');await sql.unsafe('reset role');
 await sql.unsafe(`update public.club_memberships set active=false where id='00000000-0000-0000-0000-000000000020'`);
 assert.deepEqual({...await call()},{access:false,member:false,admin:false});
 await sql.unsafe('set local role authenticated');assert.equal((await sql.unsafe('select count(*) n from public.membership_roles'))[0].n,'0');await sql.unsafe('reset role');
 await denied(`update public.club_memberships set active=null where id='00000000-0000-0000-0000-000000000020'`,'23502');
 assert.equal((await call('00000000-0000-0000-0000-000000000002')).access,false);assert.equal((await call(null)).member,false);assert.equal((await call(undefined,'')).access,false);
 await sql.unsafe(`update public.club_memberships set active=true where id='00000000-0000-0000-0000-000000000020';select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000010',true);`);
 await sql.unsafe(`insert into public.members(id,club_id,full_name,status) values('00000000-0000-0000-0000-000000000030','00000000-0000-0000-0000-000000000001','Synthetic member','active');update public.members set status='prospect' where id='00000000-0000-0000-0000-000000000030';`);
 assert.equal((await sql.unsafe(`select count(*) n from public.member_status_history where member_id='00000000-0000-0000-0000-000000000030'`))[0].n,'2');
 assert.equal((await sql.unsafe(`select count(*) n from public.member_timeline where member_id='00000000-0000-0000-0000-000000000030' and event_type='status_change'`))[0].n,'1');
 await sql.unsafe('rollback');
 report.checks.push('Synthetic Auth onboarding name/fallback/no-email rejection; duplicate/NULL slug; authenticated RBAC active/inactive/wrong role/foreign club/missing identity; permission helper denies without error; actual member status trigger writes history/timeline');
 await sql.unsafe('begin');const functionsBefore=Array.from(await sql.unsafe(`select oid,pg_get_functiondef(oid) definition from pg_proc where pronamespace='public'::regnamespace and prokind in ('f','p') order by oid`));
 await denied(readFileSync(resolve(root,'supabase/migrations/1000_bob_manager_v1_complete.sql'),'utf8'),'55000');
 assert.deepEqual(Array.from(await sql.unsafe(`select oid,pg_get_functiondef(oid) definition from pg_proc where pronamespace='public'::regnamespace and prokind in ('f','p') order by oid`)),functionsBefore);await sql.unsafe('rollback');
 report.checks.push('club_membership_id tenant policy permits active membership and hides inactive membership; NULL active rejected; replaying historical 1000 on existing schema aborts before any change');
 report.status='passed';
}catch(e){report.status='failed';report.error={code:e.code,message:e.message};process.exitCode=1;}
finally{await sql.unsafe('rollback').catch(()=>{});await sql.end();report.finished_at=new Date().toISOString();const output=originalBaseline?'PHASE_BASELINE_ORIGINAL_REBUILD_RESULTS.json':allowExtensionAdapters?'PHASE_BASELINE_REBUILD_RESULTS.json':'PHASE_BASELINE_STRICT_REBUILD_RESULTS.json';writeFileSync(resolve(root,'docs',output),JSON.stringify(report,null,2)+'\n');const historyFile=resolve(root,'docs/PHASE_BASELINE_REBUILD_ATTEMPTS.json');const history=existsSync(historyFile)?JSON.parse(readFileSync(historyFile,'utf8')):[];history.push(report);writeFileSync(historyFile,JSON.stringify(history,null,2)+'\n');}
console.log(JSON.stringify({status:report.status,database,total:report.total,applied:report.applied.length,first_failure:report.first_failure},null,2));
