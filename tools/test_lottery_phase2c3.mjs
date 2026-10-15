// Local PostgreSQL only. Fixed loopback, fresh database, synthetic fixtures.
// Usage: node tools/test_lottery_phase2c3.mjs <postgres.js/src/index.js> <schema-catalog.json>
import {readFileSync,readdirSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import {restoreCatalog} from './restore_weekly_officer_catalog.mjs';
const postgres=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const options={host:'127.0.0.1',port:55439,user:'postgres',max:1,prepare:false,onnotice:()=>{}};
const admin=postgres({...options,database:'postgres'});
const database='bob_phase2c3_'+Date.now();
await admin.unsafe(`create database ${database}`); await admin.end();
const client=postgres({...options,database});
const db={exec:s=>client.unsafe(s),query:async(s,p=[])=>({rows:await client.unsafe(s,p)})};
const root=resolve(import.meta.dirname,'..');
const read=p=>readFileSync(resolve(root,p),'utf8');
const report={database,endpoint:'127.0.0.1:55439',checks:[]};
const check=(v,s)=>{assert.ok(v,s);report.checks.push(s);console.log('PASS '+s);};
const scalar=async(s,p=[])=>Object.values((await db.query(s,p)).rows[0])[0];
try {
 report.catalog=await restoreCatalog(db,JSON.parse(readFileSync(resolve(process.argv[3]),'utf8')));
 await db.exec(read('supabase/migrations/20261013100000_rc1_authenticated_security_definer_phase2c_low_risk.sql'));
 await db.exec(read('supabase/migrations/20261013145457_rc1_weekly_officer_calendar_assignment_split.sql'));
 // Neither fixture import nor this harness contacts Supabase or any HTTP service.
 await db.exec(`set timezone='Europe/Lisbon';
 insert into auth.users(id) values
 ('10000000-0000-0000-0000-000000000001'),('10000000-0000-0000-0000-000000000002'),('10000000-0000-0000-0000-000000000003');
 insert into clubs(id,name,slug) values ('00000000-0000-0000-0000-000000000001','Fixture','fixture'),('00000000-0000-0000-0000-000000000002','Other','other');
 insert into profiles(id,full_name,email) values
 ('10000000-0000-0000-0000-000000000001','Manager','manager@example.invalid'),
 ('10000000-0000-0000-0000-000000000002','Viewer','viewer@example.invalid'),
 ('10000000-0000-0000-0000-000000000003','Outsider','outsider@example.invalid');
 insert into club_memberships(club_id,profile_id,active,access_role) values
 ('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',true,'treasurer'),
 ('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002',true,'member'),
 ('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000003',true,'treasurer');
 select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',false);
 insert into club_role_permissions(club_id,role_key,permission_key,allowed)
 select c.id,r,p,true from clubs c cross join unnest(array['treasurer','member']) r cross join unnest(array['viewLottery','viewMembers']) p where c.id='00000000-0000-0000-0000-000000000001';
 insert into club_role_permissions(club_id,role_key,permission_key,allowed)
 select id,'treasurer','manageLottery',true from clubs where id='00000000-0000-0000-0000-000000000001';
 select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',false);
 insert into members(id,club_id,full_name,status) values
 ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','A','active'),
 ('20000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','B','active');
 select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',false);
 insert into members(id,club_id,full_name,status) values
 ('20000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002','C','active');
 select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',false);
 insert into euromillions_players(id,club_id,member_id,status,numbers,stars) values
 ('30000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','active',array[1,2,3,4,5],array[1,2]);
 insert into euromillions_draw_charges(club_id,player_id,week_start,draw_date,amount)
 values ('00000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2020-01-06','2020-01-07',7.77);
 insert into treasury_accounts(club_id,name,account_type,active) values ('00000000-0000-0000-0000-000000000001','Euromilhões','fund',true)
 on conflict do nothing;
 `);
 const snapshot=()=>scalar(`select jsonb_build_object('players',(select jsonb_agg(to_jsonb(p) order by id) from euromillions_players p),
 'charges',(select jsonb_agg(to_jsonb(c) order by id) from euromillions_draw_charges c),'audit',(select count(*) from audit_log))`);
 const before=await snapshot();
 const migration=readdirSync(resolve(root,'supabase/migrations')).find(s=>s.endsWith('_rc1_euromillions_explicit_month_preparation.sql'));
 await db.exec(read('supabase/migrations/'+migration));
 assert.deepEqual(await snapshot(),before);check(true,'Migration preserves existing rows and audit without backfill');
 await db.exec(read('supabase/tests/phase2c3_lottery_regression.sql'));
 check(true,'SQL permissions, historical/current/future preparation and payment contracts pass');
 assert.deepEqual(await snapshot(),before);check(true,'Regression transaction rolls back all fixture writes');
 await db.exec(read('supabase/migrations/'+migration));
 assert.deepEqual(await snapshot(),before);check(true,'Migration reapplication preserves existing state');
 report.status='passed';
} catch(e) {report.status='failed';report.error={message:e.message,code:e.code};throw e;}
finally {writeFileSync(resolve(root,'docs/PHASE_2C3_SQL_RESULTS.json'),JSON.stringify(report,null,2));await client.end({timeout:5});}
