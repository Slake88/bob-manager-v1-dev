begin;

alter table public.members
  add column if not exists profile_id uuid;

alter table public.members
  alter column profile_id drop not null;

do $$
declare
  v_members oid := 'public.members'::regclass;
  v_profiles oid := 'public.profiles'::regclass;
  v_profile_att smallint;
  v_profiles_id_att smallint;
  v_equivalent_count integer;
  v_conflicting_count integer;
begin
  select attnum into v_profile_att
  from pg_attribute
  where attrelid = v_members and attname = 'profile_id' and not attisdropped;

  if not exists (
    select 1 from pg_attribute
    where attrelid = v_members and attname = 'profile_id'
      and atttypid = 'uuid'::regtype and not attnotnull and not attisdropped
  ) then
    raise exception 'public.members.profile_id must be nullable uuid';
  end if;

  select attnum into v_profiles_id_att
  from pg_attribute
  where attrelid = v_profiles and attname = 'id'
    and atttypid = 'uuid'::regtype and not attisdropped;

  if v_profiles_id_att is null then
    raise exception 'public.profiles.id uuid is required for members.profile_id';
  end if;

  select count(*) into v_equivalent_count
  from pg_constraint c
  where c.conrelid = v_members
    and c.contype = 'f'
    and c.confrelid = v_profiles
    and cardinality(c.conkey) = 1 and c.conkey[1] = v_profile_att
    and cardinality(c.confkey) = 1 and c.confkey[1] = v_profiles_id_att
    and c.confdeltype = 'n';

  if v_equivalent_count = 0 then
    select count(*) into v_conflicting_count
    from pg_constraint c
    where c.conrelid = v_members
      and c.contype = 'f'
      and cardinality(c.conkey) = 1 and c.conkey[1] = v_profile_att;

    if v_conflicting_count > 0 then
      raise exception 'public.members.profile_id has a conflicting foreign key';
    end if;

    alter table public.members
      add constraint members_profile_id_fkey
      foreign key (profile_id) references public.profiles(id) on delete set null;
  end if;
end;
$$;

create index if not exists members_profile_id_idx
  on public.members (profile_id)
  where profile_id is not null;

create index if not exists members_club_profile_idx
  on public.members (club_id, profile_id)
  where profile_id is not null;

commit;
