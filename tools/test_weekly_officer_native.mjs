// Native local PostgreSQL only. Fixed loopback endpoint; no production URL accepted.
// Usage: node tools/test_weekly_officer_native.mjs <postgres.js/src/index.js>
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
const postgres = (await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const options = {host:'127.0.0.1',port:55439,user:'postgres',prepare:false,onnotice:()=>{}};
const admin = postgres({...options,database:'postgres',max:1});
const database = 'bob_phase2c2_native_'+Date.now();
await admin.unsafe(`create database ${database}`);
await admin.end();
const db = postgres({...options,database,max:1});
const root = resolve(import.meta.dirname,'..');
const migrations = resolve(root,'supabase/migrations');
const report={database,endpoint:'127.0.0.1:55439',applied:[],adaptations:[],checks:[]};
const check=(value,name)=>{assert.ok(value,name);report.checks.push(name);console.log('PASS '+name);};
const scalar=async(sql,params=[])=>Object.values((await db.unsafe(sql,params))[0])[0];
try {
report.version=await scalar('select version()');
report.adaptations.push({setting:'check_function_bodies=off during baseline replay',reason:'Initial migration defines has_permission against membership_id but creates club_membership_id; bodies are kept unchanged and relevant final functions are tested at runtime.'});
await db.unsafe(`
set check_function_bodies=off;
do $$ begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role bypassrls; end if;
end $$;
create schema auth; create schema extensions; create schema storage; create schema net; create schema cron;
create function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; $$;
create function auth.role() returns text language sql stable as $$
 select nullif(current_setting('request.jwt.claim.role',true),''); $$;
grant usage on schema auth,public,storage to anon,authenticated,service_role;
alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
alter default privileges in schema public grant all on sequences to anon,authenticated,service_role;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,owner uuid,owner_id text,metadata jsonb);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
 select (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1]; $$;
create table net.local_http_capture(id bigserial primary key,url text,body jsonb,headers jsonb);
create function net.http_post(url text,body jsonb default '{}',params jsonb default '{}',headers jsonb default '{}',timeout_milliseconds integer default 5000)
returns bigint language plpgsql as $$ declare result bigint; begin
 insert into net.local_http_capture(url,body,headers) values(url,body,headers) returning id into result;
 return result; end $$;
create table cron.local_job_capture(id bigserial primary key,name text,schedule text,command text);
create function cron.schedule(name text,schedule text,command text) returns bigint language plpgsql as $$
declare result bigint; begin insert into cron.local_job_capture(name,schedule,command) values(name,schedule,command) returning id into result; return result; end $$;
`);
const files=readdirSync(migrations).filter(x=>x.endsWith('.sql')).sort();
const candidate=files.find(x=>x.endsWith('_rc1_weekly_officer_calendar_assignment_split.sql'));
for(const file of files.filter(x=>x!==candidate)) {
 report.currentMigration=file;
 let sql=readFileSync(resolve(migrations,file),'utf8');
 sql=sql.replace(/create extension if not exists (pg_net|pg_cron)(?: with schema extensions)?;/gi,(line)=>{
   report.adaptations.push({file,statement:line,replacement:'Local non-networking/non-scheduling platform adapter'});
   return '-- Platform extension provided by local test adapter.';
 });
 try {await db.unsafe(sql);report.applied.push(file);} catch(e){console.error('MIGRATION FAILED '+file+' '+e.message);throw e;}
}
console.log('Replayed baseline migrations: '+report.applied.length);
// Test implementation is appended below after baseline replay is confirmed.
report.columns=await db.unsafe("select table_name,column_name,data_type,is_nullable,column_default from information_schema.columns where table_schema='public' and table_name in ('clubs','profiles','members','club_memberships') order by table_name,ordinal_position");
} catch(error) {
 report.failure={migration:report.currentMigration,code:error.code,message:error.message};
 throw error;
} finally {
 writeFileSync(resolve(root,'docs/PHASE_2C2_NATIVE_REPLAY_RESULTS.json'),JSON.stringify(report,null,2));
 await db.end({timeout:5});
}
