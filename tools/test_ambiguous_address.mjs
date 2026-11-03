// Fixed loopback; existing disposable replay only. All fixtures rolled back.
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const root=resolve(import.meta.dirname,'..');
const before=process.argv.includes('--before');
const replay=JSON.parse(readFileSync(resolve(root,before?'docs/PHASE_AMBIGUOUS_ADDRESS_BEFORE.json':'docs/PHASE_BASELINE_REBUILD_RESULTS.json')));
assert.match(replay.database,/^bob_clean_rebuild_\d+$/);
const pg=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const sql=pg({host:'127.0.0.1',port:55440,user:'postgres',database:replay.database,max:1,prepare:false,onnotice:()=>{}});
const result={database:replay.database,before:process.argv.includes('--before'),status:'failed'};
try {
 await sql.unsafe('begin');
 await sql.unsafe('savepoint probe');
 try {
  await sql.unsafe("explain update public.members set address = nullif(trim(coalesce('Rua da Liberdade'::text, '')), '') where false");
  result.assignment='accepted';
 } catch(e) {result.assignment={code:e.code,message:e.message};await sql.unsafe('rollback to savepoint probe');}
 if(result.before) assert.notEqual(result.assignment,'accepted');
 else {
  assert.equal(result.assignment,'accepted');
  const c='00000000-0000-0000-0000-000000000001',u='00000000-0000-0000-0000-000000000010',m='00000000-0000-0000-0000-000000000030';
  await sql.unsafe(`insert into auth.users(id,email) values('${u}','address@example.invalid');
   insert into public.clubs(id,name,slug) values('${c}','Address fixture','address-fixture');
   insert into public.club_memberships(club_id,profile_id,access_role,active) values('${c}','${u}','super_admin',true);
   select set_config('request.jwt.claim.sub','${u}',true);
   insert into public.notification_preferences(club_id,profile_id,module_code,in_app_enabled,push_enabled)
    select '${c}'::uuid,'${u}'::uuid,x,false,false from unnest(array['members','fees','general']) x;
   insert into public.members(id,club_id,profile_id,full_name,status,joined_at,address)
    values('${m}','${c}','${u}','Address fixture','active','2026-01-01','Rua original');`);
  for (const address of ['  Rua da Liberdade  ', '', null]) {
   const rows=await sql.unsafe(`select public.update_own_member_profile_v2($1,null,null,$2,null,null,null,null,null,null,null,null,null) id`,[c,address]);
   assert.equal(rows[0].id,m);
   assert.equal((await sql.unsafe('select address from public.members where id=$1',[m]))[0].address,address?.trim()||null);
  }
  result.real_rpc='v2, existing real table and triggers, trimmed text/empty/null: passed; authorization code unchanged';
 }
 await sql.unsafe('savepoint emergency_probe');
 try {
  await sql.unsafe("explain update public.members set emergency_contact = coalesce(emergency_contact, '{}'::jsonb) where false");
  result.emergency_assignment='accepted';
 }catch(e){result.emergency_assignment={code:e.code,message:e.message};await sql.unsafe('rollback to savepoint emergency_probe');}
 if(result.before)assert.equal(result.emergency_assignment.code,'42703');
 else assert.equal(result.emergency_assignment,'accepted');
 result.status='passed';
} finally {await sql.unsafe('rollback');await sql.end();writeFileSync(resolve(root,`docs/PHASE_AMBIGUOUS_ADDRESS_${result.before?'BEFORE':'AFTER'}.json`),JSON.stringify(result,null,2)+'\n');}
console.log(JSON.stringify(result));
