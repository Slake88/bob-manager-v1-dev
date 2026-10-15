begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Mirror the captured production rule exactly. Preserve owner, OID and ACLs.
-- Abort on an unknown body rather than overwrite an unreviewed production edit.
do $preflight$
declare
  p pg_proc%rowtype;
begin
  select * into p from pg_proc
  where oid=to_regprocedure('public.has_club_access(uuid)');
  if not found then
    raise exception 'Missing has_club_access(uuid).' using errcode='42883';
  end if;
  if not p.prosecdef or p.provolatile<>'s' or p.proisstrict
    or p.proparallel<>'u' or p.prorettype<>'boolean'::regtype
    or p.proretset or pg_get_userbyid(p.proowner)<>'postgres'
    or (select lanname from pg_language where oid=p.prolang)<>'sql'
    or pg_get_function_arguments(p.oid)<>'target_club uuid'
    or p.proconfig is distinct from array['search_path=public']::text[]
    or md5(replace(p.prosrc, E'\r\n', E'\n')) not in (
      'b36b6374042a632a65d79f86cf867841', -- versioned baseline
      'd839b5b8aa6ba45da20d571e0163aa02' -- production snapshot, CRLF normalized
    ) then
    raise exception 'Unreviewed has_club_access contract or body drift.' using errcode='55000';
  end if;
end
$preflight$;

CREATE OR REPLACE FUNCTION public.has_club_access(target_club uuid)
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
  );
$function$;
commit;
