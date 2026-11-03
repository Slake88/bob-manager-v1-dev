begin;
-- No data backfill or assignment rebuild is executed by this migration.


create schema if not exists bob_weekly_officer_private;
revoke all on schema bob_weekly_officer_private from public, anon, authenticated, service_role;
create or replace function bob_weekly_officer_private.lock_club(target_club uuid)
returns void language plpgsql volatile security definer
set search_path = pg_catalog, public, pg_temp as $$
begin
  if target_club is null then raise exception 'Clube inválido.' using errcode='22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('weekly_officer:' || target_club::text, 0));
end;
$$;
revoke all on function bob_weekly_officer_private.lock_club(uuid)
  from public, anon, authenticated, service_role;


create or replace function public.ensure_weekly_officer_schedule_v1(target_club uuid,p_year integer)
returns integer language plpgsql security definer set search_path=pg_catalog, public, pg_temp as $$
declare v_start date; v_end date; v_first date; v_inserted integer:=0; v_current_year integer;
begin
  if (select auth.uid()) is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.' using errcode='42501';
  end if;
  if p_year is null or p_year<2020 or p_year>2100 then raise exception 'Ano inválido.'; end if;

  v_current_year:=extract(year from current_date)::int;
  if p_year<v_current_year then return 0; end if;

  perform bob_weekly_officer_private.lock_club(target_club);
  v_start:=make_date(p_year,1,1);
  v_end:=make_date(p_year,12,31);
  if p_year=v_current_year then v_start:=greatest(v_start,current_date); end if;
  v_first:=v_start + ((4-extract(dow from v_start)::int+7)%7);

  insert into public.weekly_dinners(club_id,dinner_date,dinner_kind,status,assignment_source,generated)
  select target_club,gs::date,'regular','planned','auto',true
  from generate_series(v_first::timestamp,v_end::timestamp,interval '7 day') gs
  on conflict (club_id,dinner_date,dinner_kind) do nothing;
  get diagnostics v_inserted=row_count;
  return v_inserted;
end;
$$;


create or replace function public.rebuild_weekly_officer_schedule_internal_v1(
  target_club uuid,
  p_from_date date,
  p_through_date date
)
returns void
language plpgsql
security definer
set search_path=pg_catalog, public, pg_temp
as $$
declare
  v_dinner record;
  v_member uuid;
  v_year int;
begin
  if auth.uid() is null or not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Sem autorização para recalcular a escala.' using errcode='42501';
  end if;
  perform bob_weekly_officer_private.lock_club(target_club);
  if p_from_date is null then raise exception 'Data inválida.' using errcode='22023'; end if;
  if p_through_date is null then raise exception 'Data inválida.' using errcode='22023'; end if;
  p_from_date := greatest(current_date, p_from_date);
  if p_through_date < p_from_date then return; end if;

  update public.weekly_dinners d
  set assigned_member_id=null,
      updated_at=now(),
      updated_by=coalesce((select auth.uid()),updated_by)
  where d.club_id=target_club
    and d.dinner_kind='regular'
    and d.status='planned'
    and d.assignment_source='auto'
    and d.dinner_date between p_from_date and p_through_date;

  for v_dinner in
    select d.id,d.dinner_date
    from public.weekly_dinners d
    where d.club_id=target_club
      and d.dinner_kind='regular'
      and d.status='planned'
      and d.assignment_source='auto'
      and d.assigned_member_id is null
      and d.dinner_date between p_from_date and p_through_date
    order by d.dinner_date
  loop
    v_year:=extract(year from v_dinner.dinner_date)::int;

    select r.member_id into v_member
    from public.weekly_officer_rotation r
    where r.club_id=target_club
      and public.weekly_officer_member_available_v1(
        target_club,r.member_id,v_dinner.dinner_date
      )
    order by (
      select count(*)
      from public.weekly_dinners x
      where x.club_id=target_club
        and x.dinner_kind='regular'
        and x.status in ('planned','completed')
        and x.assigned_member_id=r.member_id
        and extract(year from x.dinner_date)::int=v_year
    ) asc,
    r.rotation_order asc,
    r.joined_rotation_at asc,
    r.member_id
    limit 1;

    if v_member is not null then
      update public.weekly_dinners
      set assigned_member_id=v_member,
          assignment_source='auto',
          updated_at=now(),
          updated_by=coalesce((select auth.uid()),updated_by)
      where id=v_dinner.id;
    end if;
  end loop;
end;
$$;

create or replace function public.rebuild_weekly_officer_future_internal_v1(
  target_club uuid,
  p_from_date date
)
returns void
language plpgsql
security definer
set search_path=pg_catalog, public, pg_temp
as $$
declare
  v_year record;
  v_start date;
  v_end date;
begin
  if auth.uid() is null or not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Sem autorização para recalcular a escala.' using errcode='42501';
  end if;
  perform bob_weekly_officer_private.lock_club(target_club);
  if p_from_date is null then raise exception 'Data inválida.' using errcode='22023'; end if;
  p_from_date := greatest(current_date, p_from_date);
  for v_year in
    select distinct extract(year from d.dinner_date)::int as year_no
    from public.weekly_dinners d
    where d.club_id=target_club
      and d.dinner_kind='regular'
      and d.dinner_date>=p_from_date
    order by 1
  loop
    v_start:=greatest(p_from_date,make_date(v_year.year_no,1,1));
    v_end:=make_date(v_year.year_no,12,31);
    perform public.rebuild_weekly_officer_schedule_internal_v1(
      target_club,v_start,v_end
    );
  end loop;
end;
$$;

create or replace function public.set_weekly_officer_member_v1(
  target_club uuid,
  p_member uuid,
  p_enabled boolean,
  p_availability_status text,
  p_force_included boolean,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path=pg_catalog, public, pg_temp
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_order integer;
begin
  if not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Apenas Presidente, Vice-Presidente ou Superadmin podem gerir a escala.' using errcode='42501';
  end if;
  perform bob_weekly_officer_private.lock_club(target_club);
  if p_availability_status not in ('active','absent','inactive') then
    raise exception 'Estado de disponibilidade inválido.';
  end if;
  if not exists(select 1 from public.members where id=p_member and club_id=target_club) then
    raise exception 'Membro inválido.';
  end if;

  select to_jsonb(r) into v_old
  from public.weekly_officer_rotation r
  where r.club_id=target_club and r.member_id=p_member;

  if v_old is null then
    select coalesce(max(rotation_order),0)+10 into v_order
    from public.weekly_officer_rotation where club_id=target_club;
    insert into public.weekly_officer_rotation(
      club_id,member_id,rotation_order,enabled,availability_status,
      force_included,notes
    ) values (
      target_club,p_member,v_order,coalesce(p_enabled,true),p_availability_status,
      coalesce(p_force_included,false),nullif(btrim(coalesce(p_notes,'')),'')
    );
  else
    update public.weekly_officer_rotation
    set enabled=coalesce(p_enabled,enabled),
        availability_status=p_availability_status,
        force_included=coalesce(p_force_included,force_included),
        notes=nullif(btrim(coalesce(p_notes,'')),''),
        updated_at=now(),updated_by=(select auth.uid())
    where club_id=target_club and member_id=p_member;
  end if;

  select to_jsonb(r) into v_new
  from public.weekly_officer_rotation r
  where r.club_id=target_club and r.member_id=p_member;

  perform public.audit_event(
    target_club,'weekly_officer_member_updated','weekly_officer_rotation',
    p_member::text,v_old,v_new,null
  );
  perform public.rebuild_weekly_officer_future_internal_v1(target_club,current_date);
end;
$$;

create or replace function public.reorder_weekly_officer_v1(
  target_club uuid,
  p_member_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path=pg_catalog, public, pg_temp
as $$
declare
  v_expected int;
  v_supplied int;
  v_distinct int;
  v_member uuid;
  v_index int:=0;
begin
  if not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Apenas Presidente, Vice-Presidente ou Superadmin podem alterar a ordem.' using errcode='42501';
  end if;
  perform bob_weekly_officer_private.lock_club(target_club);
  select count(*) into v_expected from public.weekly_officer_rotation where club_id=target_club;
  v_supplied:=coalesce(array_length(p_member_ids,1),0);
  select count(distinct x) into v_distinct from unnest(coalesce(p_member_ids,array[]::uuid[])) x;
  if v_supplied<>v_expected or v_distinct<>v_expected then
    raise exception 'A lista deve conter todos os membros da rotação uma única vez.';
  end if;
  if exists(
    select 1 from unnest(p_member_ids) x
    where not exists(
      select 1 from public.weekly_officer_rotation r
      where r.club_id=target_club and r.member_id=x
    )
  ) then raise exception 'A lista contém um membro inválido.'; end if;

  foreach v_member in array p_member_ids loop
    v_index:=v_index+1;
    update public.weekly_officer_rotation
    set rotation_order=v_index*10,updated_at=now(),updated_by=(select auth.uid())
    where club_id=target_club and member_id=v_member;
  end loop;

  perform public.audit_event(
    target_club,'weekly_officer_rotation_reordered','weekly_officer_rotation',
    target_club::text,null,jsonb_build_object('member_ids',p_member_ids),null
  );
  perform public.rebuild_weekly_officer_future_internal_v1(target_club,current_date);
end;
$$;

create or replace function public.save_weekly_officer_absence_v1(
  target_club uuid,
  p_absence uuid,
  p_member uuid,
  p_absence_kind text,
  p_starts_on date,
  p_ends_on date,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog, public, pg_temp
as $$
declare
  v_id uuid;
  v_old jsonb;
  v_new jsonb;
begin
  if not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Sem autorização para gerir ausências/férias.' using errcode='42501';
  end if;
  perform bob_weekly_officer_private.lock_club(target_club);
  if p_absence_kind not in ('vacation','absence') then raise exception 'Tipo inválido.'; end if;
  if p_starts_on is null or p_ends_on is null or p_ends_on<p_starts_on then
    raise exception 'Intervalo de datas inválido.';
  end if;
  if not exists(select 1 from public.members where id=p_member and club_id=target_club) then
    raise exception 'Membro inválido.';
  end if;

  if p_absence is null then
    insert into public.weekly_officer_absences(
      club_id,member_id,absence_kind,starts_on,ends_on,notes
    ) values (
      target_club,p_member,p_absence_kind,p_starts_on,p_ends_on,
      nullif(btrim(coalesce(p_notes,'')),'')
    ) returning id into v_id;
  else
    select to_jsonb(a) into v_old from public.weekly_officer_absences a
    where a.id=p_absence and a.club_id=target_club;
    if v_old is null then raise exception 'Ausência/férias não encontrada.'; end if;
    update public.weekly_officer_absences
    set member_id=p_member,absence_kind=p_absence_kind,
        starts_on=p_starts_on,ends_on=p_ends_on,
        notes=nullif(btrim(coalesce(p_notes,'')),''),
        updated_at=now(),updated_by=(select auth.uid())
    where id=p_absence and club_id=target_club
    returning id into v_id;
  end if;

  select to_jsonb(a) into v_new from public.weekly_officer_absences a where a.id=v_id;
  perform public.audit_event(
    target_club,'weekly_officer_absence_saved','weekly_officer_absence',
    v_id::text,v_old,v_new,null
  );
  perform public.rebuild_weekly_officer_future_internal_v1(
    target_club,greatest(current_date,least(p_starts_on,(v_old->>'starts_on')::date))
  );
  return v_id;
end;
$$;

create or replace function public.delete_weekly_officer_absence_v1(
  target_club uuid,
  p_absence uuid
)
returns void
language plpgsql
security definer
set search_path=pg_catalog, public, pg_temp
as $$
declare
  v_old jsonb;
  v_start date;
begin
  if not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Sem autorização para gerir ausências/férias.' using errcode='42501';
  end if;
  perform bob_weekly_officer_private.lock_club(target_club);
  select to_jsonb(a),a.starts_on into v_old,v_start
  from public.weekly_officer_absences a
  where a.id=p_absence and a.club_id=target_club;
  if v_old is null then raise exception 'Ausência/férias não encontrada.'; end if;
  delete from public.weekly_officer_absences where id=p_absence and club_id=target_club;
  perform public.audit_event(
    target_club,'weekly_officer_absence_deleted','weekly_officer_absence',
    p_absence::text,v_old,null,null
  );
  perform public.rebuild_weekly_officer_future_internal_v1(
    target_club,greatest(current_date,v_start)
  );
end;
$$;

create or replace function public.save_weekly_dinner_v1(
  target_club uuid,
  p_dinner uuid,
  p_date date,
  p_assigned_member uuid default null,
  p_external_name text default null,
  p_dish text default null,
  p_notes text default null,
  p_status text default 'planned'
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog, public, pg_temp
as $$
declare
  v_id uuid;
  v_old public.weekly_dinners%rowtype;
  v_new public.weekly_dinners%rowtype;
  v_kind text;
  v_source text;
  v_rebuild_from date;
begin
  if not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Apenas Presidente, Vice-Presidente ou Superadmin podem alterar a escala.' using errcode='42501';
  end if;
  perform bob_weekly_officer_private.lock_club(target_club);
  if p_status not in ('planned','completed','cancelled') then
    raise exception 'Estado inválido para edição.';
  end if;
  if p_assigned_member is not null and not exists(
    select 1 from public.members where id=p_assigned_member and club_id=target_club
  ) then raise exception 'Membro inválido.'; end if;
  if p_assigned_member is not null and nullif(btrim(coalesce(p_external_name,'')),'') is not null then
    raise exception 'Escolhe um membro ou um externo, não ambos.';
  end if;

  if p_dinner is null then
    if p_date is null then raise exception 'Indica a data.'; end if;
    v_kind:='extraordinary';
    v_source:=case when nullif(btrim(coalesce(p_external_name,'')),'') is not null then 'external' else 'manual' end;
    insert into public.weekly_dinners(
      club_id,dinner_date,dinner_kind,status,assigned_member_id,external_name,
      dish,notes,assignment_source,generated
    ) values (
      target_club,p_date,'extraordinary',p_status,p_assigned_member,
      nullif(btrim(coalesce(p_external_name,'')),''),
      nullif(btrim(coalesce(p_dish,'')),''),nullif(btrim(coalesce(p_notes,'')),''),
      v_source,false
    ) returning id into v_id;
  else
    select * into v_old from public.weekly_dinners
    where id=p_dinner and club_id=target_club for update;
    if not found then raise exception 'Jantar não encontrado.'; end if;
    v_kind:=v_old.dinner_kind;
    if v_kind='regular' and p_date is distinct from v_old.dinner_date then
      raise exception 'A data de uma quinta oficial não pode ser alterada.';
    end if;
    v_source:=case
      when nullif(btrim(coalesce(p_external_name,'')),'') is not null then 'external'
      when p_assigned_member is distinct from v_old.assigned_member_id then 'manual'
      else v_old.assignment_source
    end;
    update public.weekly_dinners
    set dinner_date=case when v_kind='regular' then dinner_date else p_date end,
        status=p_status,
        assigned_member_id=p_assigned_member,
        external_name=nullif(btrim(coalesce(p_external_name,'')),''),
        dish=nullif(btrim(coalesce(p_dish,'')),''),
        notes=nullif(btrim(coalesce(p_notes,'')),''),
        assignment_source=v_source,
        updated_at=now(),updated_by=(select auth.uid())
    where id=p_dinner
    returning * into v_new;
    v_id:=p_dinner;
  end if;

  select * into v_new from public.weekly_dinners where id=v_id;
  perform public.audit_event(
    target_club,'weekly_dinner_saved','weekly_dinner',v_id::text,
    case when p_dinner is null then null else to_jsonb(v_old) end,to_jsonb(v_new),null
  );

  if v_kind='regular' then
    v_rebuild_from:=greatest(current_date,v_new.dinner_date+1);
    perform public.rebuild_weekly_officer_future_internal_v1(target_club,v_rebuild_from);
  end if;

  if v_new.assigned_member_id is not null
     and (p_dinner is null or v_old.assigned_member_id is distinct from v_new.assigned_member_id) then
    perform public.weekly_officer_notify_member_v1(
      target_club,v_new.assigned_member_id,
      'Alteração na escala de jantares',
      'Ficaste escalado para o jantar de '||to_char(v_new.dinner_date,'DD/MM/YYYY')||'.',
      'weekly_dinner',v_id
    );
  end if;

  return v_id;
end;
$$;

create or replace function public.set_weekly_dinner_closed_v1(
  target_club uuid,
  p_dinner uuid,
  p_closed boolean,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path=pg_catalog, public, pg_temp
as $$
declare
  v_old public.weekly_dinners%rowtype;
  v_new public.weekly_dinners%rowtype;
begin
  if not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Sem autorização para fechar/reabrir uma quinta-feira.' using errcode='42501';
  end if;
  perform bob_weekly_officer_private.lock_club(target_club);
  select * into v_old from public.weekly_dinners
  where id=p_dinner and club_id=target_club and dinner_kind='regular' for update;
  if not found then raise exception 'Quinta-feira oficial não encontrada.'; end if;

  update public.weekly_dinners
  set status=case when p_closed then 'closed' else 'planned' end,
      assigned_member_id=case when p_closed then null else assigned_member_id end,
      assignment_source=case when p_closed then 'auto' else 'auto' end,
      notes=coalesce(nullif(btrim(coalesce(p_notes,'')),''),notes),
      updated_at=now(),updated_by=(select auth.uid())
  where id=p_dinner
  returning * into v_new;

  perform public.audit_event(
    target_club,
    case when p_closed then 'weekly_dinner_closed' else 'weekly_dinner_reopened' end,
    'weekly_dinner',p_dinner::text,to_jsonb(v_old),to_jsonb(v_new),p_notes
  );
  perform public.rebuild_weekly_officer_future_internal_v1(
    target_club,greatest(current_date,v_old.dinner_date)
  );
end;
$$;

create or replace function public.weekly_officer_member_append_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog, public, pg_temp
as $$
declare
  v_order integer;
begin
  perform bob_weekly_officer_private.lock_club(new.club_id);
  if not exists(
    select 1 from public.weekly_officer_rotation r
    where r.club_id=new.club_id and r.member_id=new.id
  ) then
    select coalesce(max(r.rotation_order),0)+10 into v_order
    from public.weekly_officer_rotation r where r.club_id=new.club_id;
    insert into public.weekly_officer_rotation(club_id,member_id,rotation_order)
    values(new.club_id,new.id,v_order)
    on conflict (club_id,member_id) do nothing;
  end if;
  return new;
end;
$$;

-- Fixed membership roles remain the source of management authorization.
alter function public.can_manage_weekly_officer_v1(uuid)
  set search_path = pg_catalog, public, pg_temp;

create or replace function public.rebuild_weekly_officer_schedule_v1(target_club uuid, p_year integer)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog, public, pg_temp as $$
declare
  v_from date; v_to date; v_inserted integer; v_before jsonb;
  v_eligible integer; v_assigned integer; v_changed integer;
begin
  if auth.uid() is null or not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Sem autorização para recalcular a escala.' using errcode='42501';
  end if;
  if p_year is null or p_year < extract(year from current_date)::integer or p_year > 2100 then
    raise exception 'Escolhe o ano atual ou um ano futuro até 2100.' using errcode='22023';
  end if;
  perform bob_weekly_officer_private.lock_club(target_club);
  v_from := greatest(current_date,make_date(p_year,1,1));
  v_to := make_date(p_year,12,31);
  select coalesce(jsonb_object_agg(d.id::text,to_jsonb(d.assigned_member_id)),'{}'::jsonb)
    into v_before from public.weekly_dinners d
    where d.club_id=target_club and d.dinner_kind='regular' and d.status='planned'
      and d.assignment_source='auto' and d.dinner_date between v_from and v_to;
  v_inserted := public.ensure_weekly_officer_schedule_v1(target_club,p_year);
  perform public.rebuild_weekly_officer_schedule_internal_v1(target_club,v_from,v_to);
  select count(*), count(d.assigned_member_id),
    count(*) filter (where not (v_before ? d.id::text)
      or v_before->d.id::text is distinct from coalesce(to_jsonb(d.assigned_member_id),'null'::jsonb))
    into v_eligible,v_assigned,v_changed from public.weekly_dinners d
    where d.club_id=target_club and d.dinner_kind='regular' and d.status='planned'
      and d.assignment_source='auto' and d.dinner_date between v_from and v_to;
  perform public.audit_event(target_club,'weekly_officer_schedule_rebuilt','weekly_officer_rotation',
    target_club::text,null,jsonb_build_object('from',v_from,'through',v_to,
      'inserted',v_inserted,'eligible',v_eligible,'assigned',v_assigned,'changed',v_changed),null);
  return jsonb_build_object('from',v_from,'through',v_to,'inserted',v_inserted,
    'eligible',v_eligible,'assigned',v_assigned,'changed',v_changed);
end;
$$;
revoke execute on function public.rebuild_weekly_officer_schedule_v1(uuid,integer)
  from public,anon,service_role;
grant execute on function public.rebuild_weekly_officer_schedule_v1(uuid,integer) to authenticated;
revoke execute on function public.rebuild_weekly_officer_schedule_internal_v1(uuid,date,date)
  from public,anon,authenticated,service_role;
revoke execute on function public.rebuild_weekly_officer_future_internal_v1(uuid,date)
  from public,anon,authenticated,service_role;
revoke execute on function public.weekly_officer_member_append_trigger_v1()
  from public,anon,authenticated,service_role;
revoke execute on function public.ensure_weekly_officer_schedule_v1(uuid,integer) from public,anon;
grant execute on function public.ensure_weekly_officer_schedule_v1(uuid,integer) to authenticated,service_role;
commit;
