// Reproduce canonical audit/document writers and constraint contracts; rollback only.
import {readFileSync,writeFileSync} from 'node:fs';import {resolve} from 'node:path';import {pathToFileURL} from 'node:url';import assert from 'node:assert/strict';
const pg=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;const before=process.argv.includes('--before');
const {database}=JSON.parse(readFileSync(before?'docs/PHASE_FINAL_CONTRACTS_BEFORE.json':'docs/PHASE_BASELINE_REBUILD_RESULTS.json'));assert.match(database,/^bob_clean_rebuild_\d+$/);
const sql=pg({host:'127.0.0.1',port:55440,user:'postgres',database,max:1,prepare:false,onnotice:()=>{}});
const c='00000000-0000-0000-0000-000000000001',u='00000000-0000-0000-0000-000000000010',d='00000000-0000-0000-0000-000000000040',missing='00000000-0000-0000-0000-000000000099';const results=[];
async function check(name,query,expected){await sql.unsafe('savepoint probe');let actual='OK',rows;try{rows=await sql.unsafe(query);}catch(e){actual=e.code;results.push({name,actual,message:e.message,expected});}if(actual==='OK')results.push({name,actual,expected,rows});await sql.unsafe('rollback to savepoint probe');assert.equal(actual,expected,name);}
try{await sql.unsafe('begin');await sql.unsafe(`insert into auth.users(id,email) values('${u}','contracts@example.invalid');insert into public.clubs(id,name,slug) values('${c}','Final contracts','final-contracts');insert into public.club_memberships(club_id,profile_id,access_role,active) values('${c}','${u}','super_admin',true);select set_config('request.jwt.claim.sub','${u}',true);insert into public.notification_preferences(club_id,profile_id,module_code,in_app_enabled,push_enabled) values('${c}','${u}','documents',false,false);insert into public.documents(id,club_id,name,scope,sensitive) values('${d}','${c}','Contract fixture','club',false);grant select,insert,update,delete on public.documents,public.document_versions,public.document_links to authenticated;set local role authenticated;`);
await sql.unsafe('reset role');
await check('audit_event internal function with actor',`select public.audit_event('${c}','contract_check','document','${d}',null,'{"amount":1}'::jsonb,'fixture')`,before?'42703':'OK');
await sql.unsafe('set local role authenticated');
await check('begin_import real RPC',`select public.begin_import_v1('${c}','members','fixture.csv','csv','{}'::jsonb)`,before?'42703':'OK');
await check('register_document_version real RPC',`select public.register_document_version_v1('${d}','probe/new.pdf','new.pdf','application/pdf',123,'fixture')`,before?'42703':'OK');
await check('addLink versioned payload',`insert into public.document_links(club_id,document_id,link_type,linked_entity_type,linked_entity_id,label,created_by) values('${c}','${d}','related','member','${u}','Member','${u}') returning link_type,label`,before?'42703':'OK');
await sql.unsafe('reset role');
if(before){
 await sql.unsafe('alter table public.document_versions disable trigger user;alter table public.document_links disable trigger user');
 const version=`insert into public.document_versions(club_id,document_id,version_no,storage_path,file_size,is_current) values('${c}','${d}',1,'probe/unique',5,false)`;
 await check('before accepts version_no zero',version.replace(',1,',',0,'),'OK');
 await check('before accepts negative file_size',version.replace(',5,false',',-1,false'),'OK');
 await check('before accepts NULL document_id',version.replace(`'${d}'`,'null'),'OK');
 await sql.unsafe(version);await check('before accepts duplicate document/version',version.replace('probe/unique','probe/different'),'OK');await check('before accepts duplicate storage_path',version.replace(',1,',',2,'),'OK');
 const link=`insert into public.document_links(club_id,document_id,linked_entity_type,linked_entity_id) values('${c}','${d}','member','${u}')`;
 await check('before link NULL document_id',link.replace(`'${d}'`,'null'),'OK');await check('before link orphan',link.replace(`'${d}'`,`'${missing}'`),'OK');await sql.unsafe(link);await check('before accepts duplicate document/link/target',link,'OK');
}
if(!before){
 await sql.unsafe('savepoint integration');
 await sql.unsafe(`select public.audit_event('${c}','contract_check','document','${d}',null,'{"amount":1}'::jsonb,'fixture')`);
 const audit=(await sql.unsafe("select data,after_data from public.audit_log where action='contract_check'"))[0];assert.equal(audit.data.reason,'fixture');assert.equal(audit.after_data.amount,1);
 await sql.unsafe('set local role authenticated');
 const importId=(await sql.unsafe(`select public.begin_import_v1('${c}','members','fixture.csv','csv','{}'::jsonb) id`))[0].id;
 await sql.unsafe(`select public.register_document_version_v1('${d}','probe/one.pdf','one.pdf','application/pdf',123,'first')`);
 const versionId=(await sql.unsafe(`select public.register_document_version_v1('${d}','probe/two.pdf','two.pdf','application/pdf',456,'second') id`))[0].id;
 await sql.unsafe('reset role');
 assert.equal((await sql.unsafe('select data from public.audit_log where action=$1 and entity_id=$2',['import_started',importId]))[0].data.import_id,importId);
 const versions=await sql.unsafe(`select version_no,version_label,original_file_name,mime_type,file_size,is_current from public.document_versions where document_id='${d}' order by version_no`);assert.deepEqual(versions.map(x=>[x.version_no,x.version_label,x.is_current]),[[1,'1.0',false],[2,'2.0',true]]);assert.equal(versions[1].original_file_name,'two.pdf');assert.equal(versions[1].mime_type,'application/pdf');assert.equal(Number(versions[1].file_size),456);assert.equal((await sql.unsafe(`select current_version_id from public.documents where id='${d}'`))[0].current_version_id,versionId);
 results.push({name:'audit reason/import metadata persisted; version RPC 1→2 keeps one current and updates document pointer',actual:'OK',expected:'OK'});
 await sql.unsafe('rollback to savepoint integration');
 // Declarative validation is separate from the real writers above.
 await sql.unsafe('alter table public.document_versions disable trigger user;alter table public.document_links disable trigger user');
 const version=(extra='')=>`insert into public.document_versions(club_id,document_id,version_no,version_label,storage_path,file_size,is_current) values('${c}','${d}',1,'1.0','probe/unique',5,false)${extra}`;
 await check('version valid',version(),'OK');
 await check('version_no positive',version().replace(",1,'1.0'",",0,'1.0'"),'23514');
 await check('file_size nonnegative',version().replace(',5,false',',-1,false'),'23514');
 await check('version_label not null',version().replace("'1.0'",'null'),'23502');
 await check('document_id not null',version().replace(`'${d}'`,'null'),'23502');
 await check('version FK orphan',version().replace(`'${d}'`,`'${missing}'`),'23503');
 await sql.unsafe(version());
 await check('duplicate document/version',version().replace('probe/unique','probe/different'),'23505');
 await check('duplicate storage_path',version().replace(",1,'1.0'",",2,'2.0'"),'23505');
 const link=`insert into public.document_links(club_id,document_id,linked_entity_type,linked_entity_id) values('${c}','${d}','member','${u}')`;
 await check('link default related',link+' returning link_type','OK');
 await check('link document_id not null',link.replace(`'${d}'`,'null'),'23502');
 await check('link FK orphan',link.replace(`'${d}'`,`'${missing}'`),'23503');
 await sql.unsafe(link);await check('duplicate document/link/target',link,'23505');
 await sql.unsafe(`delete from public.documents where id='${d}'`);
 assert.equal((await sql.unsafe(`select count(*) n from public.document_versions where document_id='${d}'`))[0].n,'0');assert.equal((await sql.unsafe(`select count(*) n from public.document_links where document_id='${d}'`))[0].n,'0');results.push({name:'document delete cascades versions and links',actual:'OK',expected:'OK'});
}
}finally{await sql.unsafe('rollback').catch(()=>{});await sql.end();writeFileSync('docs/PHASE_FINAL_CONTRACTS_'+(before?'BEFORE':'AFTER')+'.json',JSON.stringify({database,before,scope:'Authenticated real writers with original triggers; declarative negatives explicitly disable user triggers in rollback',results},null,2)+'\n');}
console.log(JSON.stringify({passed:results.length,before}));
