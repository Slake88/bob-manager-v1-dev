// Fixed loopback only; no external credentials or production writes.
// node tools/test_reconciliation.mjs <postgres.js/src/index.js> <schema-catalog.json>
import {readFileSync,writeFileSync,readdirSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import {restoreCatalog} from './restore_weekly_officer_catalog.mjs';
const postgres=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const root=resolve(import.meta.dirname,'..');
const read=p=>readFileSync(resolve(root,p),'utf8');
const options={host:'127.0.0.1',port:55440,user:'postgres',max:1,prepare:false,onnotice:()=>{}};
const database='bob_reconciliation_'+Date.now();
const admin=postgres({...options,database:'postgres'});
await admin.unsafe(`create database ${database}`);await admin.end();
const sql=postgres({...options,database});
const db={exec:s=>sql.unsafe(s),query:async(s,p=[])=>({rows:await sql.unsafe(s,p)})};
const report={database,endpoint:'127.0.0.1:55440',checks:[]};
const migrations=readdirSync(resolve(root,'supabase/migrations'));
const nullability=read('supabase/migrations/'+migrations.find(f=>f.endsWith('_rc1_reconciliation_identity_nullability.sql')));
const access=read('supabase/migrations/'+migrations.find(f=>f.endsWith('_rc1_reconciliation_club_access.sql')));
const withoutTransaction=s=>s.replace(/^begin;/i,'').replace(/commit;\s*$/i,'');
const metadata=()=>sql.unsafe(`select p.oid,p.proname,p.proowner,p.proacl::text,p.provolatile,p.proparallel,p.proisstrict,p.prosecdef,p.proconfig,p.prorettype,p.proretset,pg_get_function_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','bob_fees_private') order by p.oid`);
const columns=()=>sql.unsafe(`select a.attrelid::regclass::text rel,a.attname,a.attnotnull,format_type(a.atttypid,a.atttypmod) type,pg_get_expr(d.adbin,d.adrelid) def from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where (a.attrelid='public.clubs'::regclass and a.attname='slug') or (a.attrelid='public.profiles'::regclass and a.attname='email') order by rel`);
const denied=async(stmt,code)=>{await sql.unsafe('savepoint rejected');let failed=false;try{await sql.unsafe(stmt);}catch(e){assert.equal(e.code,code);failed=true;}finally{await sql.unsafe('rollback to savepoint rejected');}assert.ok(failed,'Expected rejection: '+code);};
try {
 report.catalog=await restoreCatalog(db,JSON.parse(readFileSync(resolve(process.argv[3] ?? resolve(root,'tools/fixtures/reconciliation_catalog.json')),'utf8')));
 await db.exec(`create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,owner uuid,owner_id text,metadata jsonb);alter table storage.objects enable row level security;grant select,insert,update,delete on storage.objects to authenticated;`);
 for(const file of migrations.filter(f=>f>='20261013100000' && f<'20261014141853').sort()) await db.exec(read('supabase/migrations/'+file));
 report.checks.push('Existing catalog restored with constraints/RLS/triggers; 2C.1-2C.7 applied locally');
 const originalMeta=await metadata();
 const originalColumns=await columns();
 const originalDefinitions=await sql.unsafe(`select p.oid,pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','bob_fees_private') order by p.oid`);
 // Reproduce nullable baseline on populated fixtures. All changes roll back.
 await sql.unsafe('begin');
 await sql.unsafe(`alter table public.clubs alter column slug drop not null;alter table public.profiles alter column email drop not null;insert into auth.users(id) values('00000000-0000-0000-0000-000000000010');insert into public.profiles(id,full_name,email) values('00000000-0000-0000-0000-000000000010','Synthetic','fixture@example.invalid');insert into public.clubs(id,name,slug) values('00000000-0000-0000-0000-000000000001','Synthetic','fixture');`);
 const before=await sql.unsafe('select to_jsonb(c) row from public.clubs c union all select to_jsonb(p) from public.profiles p');
 await sql.unsafe(withoutTransaction(nullability));
 await sql.unsafe(withoutTransaction(nullability));
 assert.ok((await columns()).every(c=>c.attnotnull));
 assert.deepEqual(await sql.unsafe('select to_jsonb(c) row from public.clubs c union all select to_jsonb(p) from public.profiles p'),before);
 await denied(`insert into public.clubs(id,name) values('00000000-0000-0000-0000-000000000002','Missing slug')`,'23502');
 await sql.unsafe(`insert into auth.users(id) values('00000000-0000-0000-0000-000000000011')`);
 await denied(`insert into public.profiles(id,full_name) values('00000000-0000-0000-0000-000000000011','Missing email')`,'23502');
 await denied(`update public.profiles set email=null`,'23502');
 await sql.unsafe('rollback');assert.deepEqual(await columns(),originalColumns);
 report.checks.push('NULL constraints enforce omitted slug/email rejection; populated valid rows unchanged; repeatable DDL; defaults/types preserved');
 for(const table of ['clubs','profiles']) {
  await sql.unsafe('begin');
  await sql.unsafe(`alter table public.clubs alter column slug drop not null;alter table public.profiles alter column email drop not null;insert into auth.users(id) values('00000000-0000-0000-0000-000000000010');insert into public.profiles(id,full_name,email) values('00000000-0000-0000-0000-000000000010','Synthetic',${table==='profiles'?'null':"'fixture@example.invalid'"});insert into public.clubs(id,name,slug) values('00000000-0000-0000-0000-000000000001','Synthetic',${table==='clubs'?'null':"'fixture'"});`);
  const before=await columns();await denied(withoutTransaction(nullability),'23502');assert.deepEqual(await columns(),before);
  await sql.unsafe('rollback');
 }
 report.checks.push('Existing NULL slug and existing NULL email abort atomically with 23502; no backfill or partial constraint change');
 // Type compatibility branch tested with disposable citext baseline too.
 await sql.unsafe('begin');await sql.unsafe('create extension citext;alter table public.profiles alter column email type citext using email::citext;');
 await sql.unsafe(withoutTransaction(nullability));assert.equal((await columns()).find(c=>c.rel==='profiles').type,'citext');await sql.unsafe('rollback');
 report.checks.push('citext baseline accepted without type conversion; text production type preserved separately');
 // Unknown function must not be replaced. Local permission contract unchanged.
 await sql.unsafe('begin');
 await sql.unsafe(`create or replace function public.has_club_access(target_club uuid) returns boolean language sql stable security definer set search_path=public as $$ select true $$;`);
 await denied(withoutTransaction(access),'55000');await sql.unsafe('rollback');
 await sql.unsafe('begin');await sql.unsafe('drop function public.has_club_access(uuid) cascade');await denied(withoutTransaction(access),'42883');await sql.unsafe('rollback');
 report.checks.push('Unknown definition and missing function reject atomically; no unreviewed replacement');
 // Compare old baseline vs production behavior for active=true/false/NULL,
 // missing identity, no membership and foreign club, under authenticated role.
 await sql.unsafe('begin');
 await sql.unsafe(`alter table public.club_memberships alter column active drop not null;insert into auth.users(id) values('00000000-0000-0000-0000-000000000010');insert into public.profiles(id,full_name,email) values('00000000-0000-0000-0000-000000000010','Synthetic','fixture@example.invalid');insert into public.clubs(id,name,slug) values('00000000-0000-0000-0000-000000000001','Synthetic','fixture');insert into public.club_memberships(club_id,profile_id,active) values('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000010',null);`);
 const inventory=JSON.parse(read('docs/PHASE_RECONCILIATION_REPOSITORY_INVENTORY.json'));
 await sql.unsafe(inventory.items.find(f=>f.name==='has_club_access').definitions.at(-1).definition);
 const call=async(club='00000000-0000-0000-0000-000000000001',uid='00000000-0000-0000-0000-000000000010')=>{
  await sql.unsafe('select set_config(\'request.jwt.claim.sub\',$1,true)',[uid]);await sql.unsafe('set local role authenticated');
  const value=(await sql.unsafe('select public.has_club_access($1::uuid) allowed',[club]))[0].allowed;await sql.unsafe('reset role');return value;
 };
 assert.equal(await call(),true);
 await sql.unsafe(withoutTransaction(access));assert.equal(await call(),false);
 for(const active of [true,false]) {await sql.unsafe('update public.club_memberships set active=$1',[active]);assert.equal(await call(),active);}
 assert.equal(await call('00000000-0000-0000-0000-000000000002'),false);
 assert.equal(await call(null),false);assert.equal(await call(undefined,''),false);
 assert.equal(await call(undefined,'00000000-0000-0000-0000-000000000011'),false);
 await sql.unsafe(withoutTransaction(access));assert.equal(await call(),false);
 await sql.unsafe('rollback');
 report.checks.push('Repo NULL-active access reproduced, then denied; TRUE/FALSE, foreign club, NULL club, missing identity, missing membership covered; authenticated/RLS path and reapplication tested');
 await sql.unsafe(nullability);await sql.unsafe(access);await sql.unsafe(access);
 assert.deepEqual(await metadata(),originalMeta);
 assert.deepEqual(await columns(),originalColumns);
 assert.deepEqual(Array.from(await sql.unsafe(`select p.oid,pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','bob_fees_private') and p.proname<>'has_club_access' order by p.oid`)),Array.from(originalDefinitions).filter(x=>!originalMeta.some(m=>m.oid===x.oid && m.proname==='has_club_access')));
 report.checks.push('Production baseline unchanged except canonical has_club_access text; all owners/OIDs/ACLs/config/volatility/strictness/parallelism/signatures and other function definitions preserved');
 report.status='passed';
} catch(e) {report.status='failed';report.error={message:e.message.slice(0,1000),code:e.code};process.exitCode=1;}
finally {await sql.unsafe('rollback').catch(()=>{});await sql.end();writeFileSync(resolve(root,'docs/PHASE_RECONCILIATION_SQL_RESULTS.json'),JSON.stringify(report,null,2)+'\n');}
console.log(JSON.stringify(report,null,2));
