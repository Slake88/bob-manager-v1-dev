-- Exact active contracts captured 2026-10-14; no legacy functions.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
-- Effective production type: reject drift; do not convert an existing populated schema.
do $$ begin
 if (select atttypid from pg_attribute where attrelid='public.profiles'::regclass and attname='email' and not attisdropped) is distinct from 'text'::regtype::oid then
  raise exception 'profiles.email must be production text; no automatic conversion' using errcode='55000';
 end if;
end $$;

do $bootstrap$ declare p pg_proc%rowtype; begin
 select * into p from pg_proc where oid=to_regprocedure('public.handle_new_user()');
 if found then
  if not p.prosecdef or p.provolatile<>'v' or p.proisstrict or p.proparallel<>'u' or p.proretset
    or p.prorettype<>'trigger'::regtype or pg_get_userbyid(p.proowner)<>'postgres'
    or (select lanname from pg_language where oid=p.prolang)<>'plpgsql'
    or pg_get_function_arguments(p.oid)<>''
    or p.proconfig is distinct from array['search_path=public']::text[] or md5(replace(p.prosrc,E'\r\n',E'\n'))<>'d09d2d62677178915cf6911a86adb79a' then
   raise exception 'Unreviewed handle_new_user contract' using errcode='55000';
  end if;
 else
  execute $ddl$CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.profiles (
    id,
    full_name,
    email
  )
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'full_name',
      split_part(new.email, '@', 1)
    ),
    new.email
  )
  on conflict (id) do nothing;

  return new;
end;
$function$;$ddl$;
  revoke all on function public.handle_new_user() from public,anon,authenticated,service_role;
  grant execute on function public.handle_new_user() to service_role;
 end if;
end $bootstrap$;

do $bootstrap$ declare p pg_proc%rowtype; begin
 select * into p from pg_proc where oid=to_regprocedure('public.has_club_role(uuid,text[])');
 if found then
  if not p.prosecdef or p.provolatile<>'s' or p.proisstrict or p.proparallel<>'u' or p.proretset
    or p.prorettype<>'boolean'::regtype or pg_get_userbyid(p.proowner)<>'postgres'
    or (select lanname from pg_language where oid=p.prolang)<>'sql'
    or pg_get_function_arguments(p.oid)<>'target_club uuid, allowed_roles text[]'
    or p.proconfig is distinct from array['search_path=public']::text[] or md5(replace(p.prosrc,E'\r\n',E'\n'))<>'d20dbc0bc410cd7afe5b584d9311dfba' then
   raise exception 'Unreviewed has_club_role contract' using errcode='55000';
  end if;
 else
  execute $ddl$CREATE OR REPLACE FUNCTION public.has_club_role(target_club uuid, allowed_roles text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.club_memberships
    where club_id = target_club
      and profile_id = auth.uid()
      and active = true
      and access_role = any(allowed_roles)
  );
$function$;$ddl$;
  revoke all on function public.has_club_role(uuid,text[]) from public,anon,authenticated,service_role;
  grant execute on function public.has_club_role(uuid,text[]) to authenticated,service_role;
 end if;
end $bootstrap$;

do $trigger$ declare t pg_trigger%rowtype; begin
 select * into t from pg_trigger where tgrelid='auth.users'::regclass and tgname='on_auth_user_created' and not tgisinternal;
 if found then
  if t.tgfoid<>to_regprocedure('public.handle_new_user()') or t.tgtype<>5 or t.tgenabled<>'O' or t.tgqual is not null or t.tgnargs<>0 then
   raise exception 'Unreviewed Auth onboarding trigger' using errcode='55000';
  end if;
 else
  create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
 end if;
end $trigger$;
-- Structural reconciliation after inventory_locations exists. No backfill/cascade.
do $locations$ declare r record; existing record; begin
 for r in select * from (values
 ('stock_movements','from_location_id','SET NULL','n'),
 ('stock_movements','to_location_id','SET NULL','n'),
 ('stock_lots','location_id','RESTRICT','r'),
 ('stock_reservations','location_id','RESTRICT','r')
 ) x(tbl,col,delete_action,delete_code) loop
  select c.* into existing from pg_constraint c
   where c.conrelid=to_regclass('public.'||r.tbl) and c.conname=r.tbl||'_'||r.col||'_fkey';
  if found then
   if existing.contype<>'f' or existing.confrelid<>'public.inventory_locations'::regclass
    or existing.confdeltype::text<>r.delete_code or existing.confupdtype<>'a'
    or existing.conkey<>array[(select attnum from pg_attribute where attrelid=existing.conrelid and attname=r.col)]::smallint[]
    or existing.confkey<>array[(select attnum from pg_attribute where attrelid=existing.confrelid and attname='id')]::smallint[]
    or not existing.convalidated or existing.condeferrable then
     raise exception 'Unreviewed location FK %.%',r.tbl,r.col using errcode='55000';
   end if;
  else
   execute format('alter table public.%I add constraint %I foreign key(%I) references public.inventory_locations(id) on delete %s on update no action',r.tbl,r.tbl||'_'||r.col||'_fkey',r.col,r.delete_action);
  end if;
 end loop;
end $locations$;
commit;
