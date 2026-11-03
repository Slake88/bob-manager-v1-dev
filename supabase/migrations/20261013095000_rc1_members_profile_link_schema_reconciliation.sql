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

do $$
declare
  v_index record;
  v_index_oid oid;
  v_relkind "char";
  v_is_unique boolean;
  v_is_valid boolean;
  v_is_ready boolean;
  v_key_count smallint;
  v_column_count smallint;
  v_column_attnums smallint[];
  v_predicate text;
  v_normalized_predicate text;
begin
  for v_index in
    select * from (values
      ('members_profile_id_idx', array[
        (select attnum from pg_attribute where attrelid='public.members'::regclass
          and attname='profile_id' and not attisdropped)
      ]::smallint[]),
      ('members_club_profile_idx', array[
        (select attnum from pg_attribute where attrelid='public.members'::regclass
          and attname='club_id' and not attisdropped),
        (select attnum from pg_attribute where attrelid='public.members'::regclass
          and attname='profile_id' and not attisdropped)
      ]::smallint[])
    ) as expected(index_name, column_attnums)
  loop
    select c.oid, c.relkind
      into v_index_oid, v_relkind
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname=v_index.index_name;

    if not found then
      if v_index.index_name='members_profile_id_idx' then
        execute 'create index members_profile_id_idx on public.members (profile_id) where profile_id is not null';
      else
        execute 'create index members_club_profile_idx on public.members (club_id, profile_id) where profile_id is not null';
      end if;
      continue;
    end if;

    if v_relkind <> 'i' then
      raise exception 'Schema conflict: public.% exists but is not an index',v_index.index_name;
    end if;

    select i.indisunique, i.indisvalid, i.indisready,
      i.indnkeyatts, i.indnatts,
      array(
        select i.indkey[position]::smallint
        from generate_series(0,i.indnatts-1) as positions(position)
        order by position
      ),
      pg_get_expr(i.indpred,i.indrelid)
    into v_is_unique, v_is_valid, v_is_ready, v_key_count, v_column_count,
      v_column_attnums, v_predicate
    from pg_index i
    where i.indexrelid=v_index_oid and i.indrelid='public.members'::regclass;

    if not found then
      raise exception 'Schema conflict: public.% is not an index on public.members',v_index.index_name;
    end if;

    v_normalized_predicate := lower(coalesce(v_predicate,''));
    v_normalized_predicate := regexp_replace(v_normalized_predicate,'[[:space:]()]','','g');
    v_normalized_predicate := replace(v_normalized_predicate,'"','');
    v_normalized_predicate := replace(v_normalized_predicate,'public.members.','');
    v_normalized_predicate := replace(v_normalized_predicate,'members.','');

    if v_is_unique
      or not v_is_valid
      or not v_is_ready
      or v_key_count <> cardinality(v_index.column_attnums)
      or v_column_count <> cardinality(v_index.column_attnums)
      or v_column_attnums is distinct from v_index.column_attnums
      or v_normalized_predicate <> 'profile_idisnotnull' then
      raise exception
        'Schema conflict: public.% must be a valid, ready, non-unique index on public.members (%) where profile_id is not null; found columns %, predicate "%" (unique %, valid %, ready %)',
        v_index.index_name,
        case when v_index.index_name='members_profile_id_idx'
          then 'profile_id' else 'club_id, profile_id' end,
        v_column_attnums,v_predicate,v_is_unique,v_is_valid,v_is_ready;
    end if;
  end loop;
end;
$$;

commit;
