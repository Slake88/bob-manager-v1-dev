-- Phase 2C.4: never pick or delete a duplicate automatically.
begin;
set local lock_timeout = '10s';
lock table public.members in share row exclusive mode;

do $$
begin
  if exists (
    select 1 from public.members
    where profile_id is not null
    group by club_id, profile_id having count(*) > 1
  ) then
    raise exception 'Duplicate members(club_id, profile_id); reconcile links before retrying'
      using errcode = '23505';
  end if;

  -- Fail closed on a colliding name rather than accepting an unrelated index.
  if to_regclass('public.members_club_profile_unique') is not null then
    if not exists (
      select 1 from pg_index i
      join pg_class c on c.oid = i.indexrelid
      join pg_am a on a.oid = c.relam
      where i.indexrelid = 'public.members_club_profile_unique'::regclass
        and i.indrelid = 'public.members'::regclass
        and a.amname = 'btree'
        and i.indisunique and i.indisvalid and i.indisready
        and i.indnkeyatts = 2 and i.indnatts = 2
        and i.indexprs is null
        and i.indkey[0] = (select attnum from pg_attribute where attrelid = i.indrelid and attname = 'club_id')
        and i.indkey[1] = (select attnum from pg_attribute where attrelid = i.indrelid and attname = 'profile_id')
        and pg_get_expr(i.indpred, i.indrelid) = '(profile_id IS NOT NULL)'
    ) then
      raise exception 'members_club_profile_unique exists with an incompatible definition'
        using errcode = '55000';
    end if;
  else
    create unique index members_club_profile_unique
      on public.members (club_id, profile_id) where profile_id is not null;
  end if;
end $$;
commit;
