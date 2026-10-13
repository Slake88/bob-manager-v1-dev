// Restore application schema metadata only into a fresh local test database.
// auth/storage/net are local adapters, not external Supabase services.
import assert from 'node:assert/strict';
const qi=value=>'"'+value.replaceAll('"','""')+'"';
const qs=value=>"'"+value.replaceAll("'","''")+"'";
const object=t=>`${qi(t.schema)}.${qi(t.name)}`;
const role=value=>value==='PUBLIC'?'PUBLIC':qi(value);
export async function restoreCatalog(db,snapshot) {
  assert.ok(snapshot.relations.every(t=>t.kind==='r'),'Only ordinary tables supported');
  assert.ok(snapshot.domains.length===0,'Domain support requires explicit restore');
  assert.ok(snapshot.functions.every(f=>f.owner==='postgres'),'Unexpected function owner');
  for(const f of snapshot.functions) {
    assert.ok(!/pg_read_file|pg_read_binary_file|COPY[\s\S]*?PROGRAM|dblink|LANGUAGE (?:plpython|plperlu|c)\b/i.test(f.definition), 'Unexpected privileged function: '+f.name);
  }
  await db.exec(`
  set check_function_bodies=off;
  do $$ begin
   if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
   if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
   if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
  end $$;
  create schema auth; create schema storage; create schema net; create schema extensions;
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; $$;
  create function auth.role() returns text language sql stable as $$
    select nullif(current_setting('request.jwt.claim.role',true),''); $$;
  create table auth.users(id uuid primary key);
  grant usage on schema auth,storage to authenticated,anon,service_role;
  create function storage.foldername(name text) returns text[] language sql immutable as $$
    select (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1]; $$;
  create table net.local_http_capture(id bigserial primary key,url text,body jsonb,headers jsonb);
  create function net.http_post(url text,body jsonb default '{}',params jsonb default '{}',headers jsonb default '{}',timeout_milliseconds integer default 5000)
    returns bigint language plpgsql as $$ declare result bigint; begin
    insert into net.local_http_capture(url,body,headers) values(url,body,headers) returning id into result;
    return result; end $$;
  create extension unaccent with schema extensions;
  create extension pgcrypto with schema extensions;
  create extension "uuid-ossp" with schema extensions;
  `);
  for(const s of snapshot.schemas) {
    if(s.name!=='public') await db.exec(`create schema ${qi(s.name)}`);
  }
  for(const type of snapshot.enums) {
    await db.exec(`create type ${object(type)} as enum (${type.values.map(qs).join(',')})`);
  }
  // Identity sequences are created with their owning columns. No sequence data is copied.
  for(const sequence of snapshot.sequences) {
    if(snapshot.relations.some(t=>t.columns.some(c=>c.identity && sequence.name===t.name+'_'+c.name+'_seq'))) continue;
    await db.exec(`create sequence ${object(sequence)} as ${sequence.type} start ${sequence.start} increment ${sequence.increment}`);
  }
  for(const table of snapshot.relations) {
    const columns=table.columns.map(c=>{
      let ddl=`${qi(c.name)} ${c.type}`;
      if(c.identity) ddl+=` generated ${c.identity==='a'?'always':'by default'} as identity`;
      if(c.generated) ddl+=` generated always as (${c.default}) stored`;
      if(c.notnull) ddl+=' not null';
      return ddl;
    });
    await db.exec(`create table ${object(table)} (${columns.join(',\n')})`);
  }
  for(const f of snapshot.functions) await db.exec(f.definition);
  // Forward references are loaded; runtime tests exercise relevant function bodies.
  await db.exec('set check_function_bodies=on');
  for(const table of snapshot.relations) {
    for(const c of table.columns.filter(c=>c.default && !c.identity && !c.generated)) {
      await db.exec(`alter table ${object(table)} alter column ${qi(c.name)} set default ${c.default}`);
    }
    for(const c of table.constraints.filter(c=>c.type!=='f')) {
      await db.exec(`alter table ${object(table)} add constraint ${qi(c.name)} ${c.definition}`);
    }
  }
  for(const table of snapshot.relations) {
    for(const c of table.constraints.filter(c=>c.type==='f')) {
      await db.exec(`alter table ${object(table)} add constraint ${qi(c.name)} ${c.definition}`);
    }
    for(const idx of table.indexes) await db.exec(idx);
    for(const trigger of table.triggers) {
      await db.exec(trigger.definition);
      if(trigger.enabled==='D') await db.exec(`alter table ${object(table)} disable trigger ${qi(trigger.name)}`);
      if(trigger.enabled==='A') await db.exec(`alter table ${object(table)} enable always trigger ${qi(trigger.name)}`);
      if(trigger.enabled==='R') await db.exec(`alter table ${object(table)} enable replica trigger ${qi(trigger.name)}`);
    }
    if(table.rls) await db.exec(`alter table ${object(table)} enable row level security`);
    if(table.force_rls) await db.exec(`alter table ${object(table)} force row level security`);
    for(const p of table.policies) {
      const cmd={'*':'ALL',r:'SELECT',a:'INSERT',w:'UPDATE',d:'DELETE'}[p.command];
      await db.exec(`create policy ${qi(p.name)} on ${object(table)} as ${p.permissive?'PERMISSIVE':'RESTRICTIVE'} for ${cmd} to ${p.roles.map(role).join(',')}${p.using?' using ('+p.using+')':''}${p.check?' with check ('+p.check+')':''}`);
    }
    await db.exec(`revoke all on ${object(table)} from public,anon,authenticated,service_role`);
    for(const grant of table.acl.filter(g=>g.grantee!=='postgres')) {
      await db.exec(`grant ${grant.privilege} on ${object(table)} to ${role(grant.grantee)}`);
    }
    for(const grant of table.column_acl.filter(g=>g.grantee!=='postgres')) {
      await db.exec(`grant ${grant.privilege} (${qi(grant.column)}) on ${object(table)} to ${role(grant.grantee)}`);
    }
  }
  for(const f of snapshot.functions) {
    const signature=`${object(f)}(${f.identity})`;
    await db.exec(`revoke all on function ${signature} from public,anon,authenticated,service_role`);
    for(const grant of f.acl.filter(g=>g.grantee!=='postgres')) {
      await db.exec(`grant ${grant.privilege} on function ${signature} to ${role(grant.grantee)}`);
    }
  }
  for(const s of snapshot.schemas) {
    await db.exec(`revoke all on schema ${qi(s.name)} from public,anon,authenticated,service_role`);
    for(const grant of s.acl.filter(g=>g.grantee!=='postgres')) {
      await db.exec(`grant ${grant.privilege} on schema ${qi(s.name)} to ${role(grant.grantee)}`);
    }
  }
  // Check actual restored column types/nullability against the captured catalog.
  for(const table of snapshot.relations) {
    const rows=(await db.query(`select a.attname name,format_type(a.atttypid,a.atttypmod) type,a.attnotnull as "notnull"
      from pg_attribute a where a.attrelid=$1::regclass and a.attnum>0 and not a.attisdropped order by a.attnum`,[object(table)])).rows;
    assert.deepEqual(rows.map(c=>({...c})),table.columns.map(c=>({name:c.name,type:c.type,notnull:c.notnull})),table.name+' columns');
    const constraints=(await db.query(`select conname name,contype type,pg_get_constraintdef(oid,true) definition
      from pg_constraint where conrelid=$1::regclass order by conname`,[object(table)])).rows;
    assert.deepEqual(constraints.map(c=>({...c})),table.constraints,table.name+' constraints');
    const triggers=(await db.query(`select tgname name,pg_get_triggerdef(oid,true) definition,tgenabled enabled
      from pg_trigger where tgrelid=$1::regclass and not tgisinternal order by tgname`,[object(table)])).rows;
    assert.deepEqual(triggers.map(c=>({...c})),[...table.triggers].sort((a,b)=>a.name.localeCompare(b.name)),table.name+' triggers');
    const counts=(await db.query(`select relrowsecurity rls,relforcerowsecurity force_rls from pg_class where oid=$1::regclass`,[object(table)])).rows[0];
    assert.deepEqual({...counts},{rls:table.rls,force_rls:table.force_rls},table.name+' RLS');
    const acl=(await db.query(`select coalesce(r.rolname,'PUBLIC') grantee,a.privilege_type privilege
      from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
      left join pg_roles r on r.oid=a.grantee where c.oid=$1::regclass`,[object(table)])).rows;
    const ordered=x=>x.map(c=>({...c})).sort((a,b)=>(a.grantee+a.privilege).localeCompare(b.grantee+b.privilege));
    assert.deepEqual(ordered(acl),ordered(table.acl),table.name+' ACL');
  }
  for(const f of snapshot.functions) {
    const signature=`${object(f)}(${f.identity})`;
    const definition=(await db.query(`select pg_get_functiondef(p.oid) definition from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace where p.proname=$1 and n.nspname=$2
      and pg_get_function_identity_arguments(p.oid)=$3`,[f.name,f.schema,f.identity])).rows[0].definition;
    assert.equal(definition.replaceAll('\r\n','\n'),f.definition.replaceAll('\r\n','\n'),f.name+' definition');
    for(const r of ['anon','authenticated','service_role']) {
      const allowed=(await db.query(`select has_function_privilege($1,
        (select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where p.proname=$2 and n.nspname=$3 and pg_get_function_identity_arguments(p.oid)=$4),
        'EXECUTE') allowed`,[r,f.name,f.schema,f.identity])).rows[0].allowed;
      assert.equal(allowed,f.acl.some(g=>g.grantee===r||g.grantee==='PUBLIC'),f.name+' '+r+' execution ACL');
    }
  }
  return {tables:snapshot.relations.length,functions:snapshot.functions.length,
    enums:snapshot.enums.length,triggers:snapshot.relations.reduce((n,t)=>n+t.triggers.length,0),
    captured_at:snapshot.captured_at,sourceVersion:snapshot.version};
}
