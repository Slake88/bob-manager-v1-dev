// Local PostgreSQL only. Fixed loopback, fresh database, synthetic fixtures.
// Usage: node tools/test_fees_phase2c5.mjs <postgres.js/src/index.js> <schema-catalog.json>
import {readFileSync,readdirSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import {restoreCatalog} from './restore_weekly_officer_catalog.mjs';
const postgres=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const options={host:'127.0.0.1',port:55439,user:'postgres',max:1,prepare:false,onnotice:()=>{}};
const admin=postgres({...options,database:'postgres'});
const database='bob_phase2c5_'+Date.now();
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
 for(const file of readdirSync(resolve(root,'supabase/migrations')).filter(f=>f>='20261013100000' && f<'20261014100444').sort()) await db.exec(read('supabase/migrations/'+file));
 const migration=read('supabase/migrations/20261014100444_rc1_explicit_fee_preparation.sql');
 await db.exec(migration);
 // Commit synthetic fixtures only in this disposable loopback database for the two-connection check.
 await db.exec(read('supabase/tests/phase2c5_fees_regression.sql').replace(/rollback;\s*$/, 'commit;'));
 await db.exec("select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',false); update user_permission_overrides set allowed=true");
 const peer=postgres({...options,database});
 const call=async c=>{await c.unsafe("select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',false)");await c.unsafe('set role authenticated');await c.unsafe("select public.prepare_member_fees_year_v1('00000000-0000-0000-0000-000000000001',2099)");await c.unsafe('reset role');};
 try {await Promise.all([call(client),call(peer)]);} finally {await peer.end();}
 assert.equal(Number(await scalar("select count(*) from fee_obligations where reference_year=2099")),24);
 check(true,'Concurrent preparations serialize without duplicate obligations');
 check(true,'Auth, club, permission, temporal guards, grants, explicit generation and immutable history');
 const before=await scalar("select count(*) from audit_log");
 await db.exec(migration);
 assert.equal(await scalar("select count(*) from audit_log"),before);
 check(true,'Migration reapplication performs no business writes');
 report.status='passed';
} catch(e) {report.status='failed';report.error={message:e.message,code:e.code};throw e;}
finally {writeFileSync(resolve(root,'docs/PHASE_2C5_SQL_RESULTS.json'),JSON.stringify(report,null,2));await client.end({timeout:5});}
