-- Commit 12 — Oficial da Semana / Escala de Jantares

create table if not exists public.weekly_officer_rotation (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  rotation_order integer not null,
  enabled boolean not null default true,
  availability_status text not null default 'active'
    check (availability_status in ('active','absent','inactive')),
  force_included boolean not null default false,
  joined_rotation_at date not null default current_date,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  unique (club_id, member_id)
);

create index if not exists weekly_officer_rotation_club_order_idx
  on public.weekly_officer_rotation(club_id, rotation_order);

create table if not exists public.weekly_officer_absences (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  absence_kind text not null default 'vacation'
    check (absence_kind in ('vacation','absence')),
  starts_on date not null,
  ends_on date not null,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  check (ends_on >= starts_on)
);

create index if not exists weekly_officer_absences_lookup_idx
  on public.weekly_officer_absences(club_id, member_id, starts_on, ends_on);

create table if not exists public.weekly_dinners (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  dinner_date date not null,
  dinner_kind text not null default 'regular'
    check (dinner_kind in ('regular','extraordinary')),
  status text not null default 'planned'
    check (status in ('planned','closed','completed','cancelled')),
  assigned_member_id uuid references public.members(id) on delete set null,
  external_name text,
  dish text,
  notes text,
  assignment_source text not null default 'auto'
    check (assignment_source in ('auto','manual','swap','external')),
  generated boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  unique (club_id, dinner_date, dinner_kind),
  check (assigned_member_id is null or nullif(btrim(coalesce(external_name,'')),'') is null)
);

create index if not exists weekly_dinners_club_date_idx
  on public.weekly_dinners(club_id, dinner_date);
create index if not exists weekly_dinners_member_date_idx
  on public.weekly_dinners(club_id, assigned_member_id, dinner_date);

create table if not exists public.weekly_officer_swap_requests (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  dinner_id uuid not null references public.weekly_dinners(id) on delete cascade,
  requester_member_id uuid not null references public.members(id) on delete cascade,
  requested_member_id uuid not null references public.members(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','accepted','rejected','applied','cancelled')),
  requester_note text,
  response_note text,
  manager_note text,
  responded_at timestamptz,
  responded_by uuid,
  applied_at timestamptz,
  applied_by uuid,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  check (requester_member_id <> requested_member_id)
);

create unique index if not exists weekly_officer_swap_pending_unique
  on public.weekly_officer_swap_requests(dinner_id, requester_member_id, requested_member_id)
  where status in ('pending','accepted');

-- Fixed-role management rule approved for this module.
create or replace function public.can_manage_weekly_officer_v1(target_club uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.club_memberships cm
      where cm.club_id=target_club
        and cm.profile_id=(select auth.uid())
        and cm.active=true
        and cm.access_role in ('super_admin','president','vice_president')
    );
$$;

create or replace function public.current_weekly_officer_member_v1(target_club uuid)
returns uuid
language sql
stable
security definer
set search_path=public
as $$
  select m.id
  from public.members m
  where m.club_id=target_club
    and m.profile_id=(select auth.uid())
  limit 1;
$$;

create or replace function public.weekly_officer_member_available_v1(
  target_club uuid,
  p_member uuid,
  p_date date
)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists (
    select 1
    from public.weekly_officer_rotation r
    join public.members m on m.id=r.member_id and m.club_id=r.club_id
    where r.club_id=target_club
      and r.member_id=p_member
      and (
        r.force_included=true
        or (
          r.enabled=true
          and r.availability_status='active'
          and m.status::text not in ('suspended','former','deceased')
          and not exists (
            select 1
            from public.weekly_officer_absences a
            where a.club_id=target_club
              and a.member_id=p_member
              and p_date between a.starts_on and a.ends_on
          )
        )
      )
  );
$$;

create or replace function public.weekly_officer_notify_member_v1(
  target_club uuid,
  p_member uuid,
  p_title text,
  p_body text,
  p_entity_type text,
  p_entity_id uuid
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile uuid;
  v_in_app boolean;
begin
  select m.profile_id into v_profile
  from public.members m
  where m.id=p_member and m.club_id=target_club;

  if v_profile is null then return; end if;

  select np.in_app_enabled into v_in_app
  from public.notification_preferences np
  where np.club_id=target_club
    and np.profile_id=v_profile
    and np.module_code='weekly_officer';

  if coalesce(v_in_app,true)=false then return; end if;

  insert into public.notifications(
    club_id,profile_id,title,body,notification_type,module_code,priority,
    entity_type,entity_id,action_route,metadata
  ) values (
    target_club,v_profile,p_title,p_body,'info','weekly_officer','normal',
    p_entity_type,p_entity_id,'weekly_officer',jsonb_build_object('module_code','weekly_officer')
  );
end;
$$;

-- Internal rebuild: keeps manual/swap assignments, recalculates only automatic future rows.
create or replace function public.rebuild_weekly_officer_schedule_internal_v1(
  target_club uuid,
  p_from_date date,
  p_through_date date
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_dinner record;
  v_member uuid;
  v_year int;
begin
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
set search_path=public
as $$
declare
  v_year record;
  v_start date;
  v_end date;
begin
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

create or replace function public.ensure_weekly_officer_schedule_v1(
  target_club uuid,
  p_year integer
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_start date;
  v_end date;
  v_first date;
  v_inserted integer:=0;
begin
  if (select auth.uid()) is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.';
  end if;
  if p_year<2020 or p_year>2100 then raise exception 'Ano inválido.'; end if;

  v_start:=make_date(p_year,1,1);
  v_end:=make_date(p_year,12,31);
  if p_year=extract(year from current_date)::int then
    v_start:=greatest(v_start,current_date);
  end if;

  v_first:=v_start + ((4-extract(dow from v_start)::int+7)%7);

  insert into public.weekly_dinners(
    club_id,dinner_date,dinner_kind,status,assignment_source,generated
  )
  select target_club,gs::date,'regular','planned','auto',true
  from generate_series(v_first::timestamp,v_end::timestamp,interval '7 day') gs
  on conflict (club_id,dinner_date,dinner_kind) do nothing;
  get diagnostics v_inserted=row_count;

  perform public.rebuild_weekly_officer_schedule_internal_v1(
    target_club,v_first,v_end
  );
  return v_inserted;
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
set search_path=public
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_order integer;
begin
  if not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Apenas Presidente, Vice-Presidente ou Superadmin podem gerir a escala.';
  end if;
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
set search_path=public
as $$
declare
  v_expected int;
  v_supplied int;
  v_distinct int;
  v_member uuid;
  v_index int:=0;
begin
  if not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Apenas Presidente, Vice-Presidente ou Superadmin podem alterar a ordem.';
  end if;
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
set search_path=public
as $$
declare
  v_id uuid;
  v_old jsonb;
  v_new jsonb;
begin
  if not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Sem autorização para gerir ausências/férias.';
  end if;
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
    target_club,greatest(current_date,p_starts_on)
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
set search_path=public
as $$
declare
  v_old jsonb;
  v_start date;
begin
  if not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Sem autorização para gerir ausências/férias.';
  end if;
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
set search_path=public
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
    raise exception 'Apenas Presidente, Vice-Presidente ou Superadmin podem alterar a escala.';
  end if;
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
set search_path=public
as $$
declare
  v_old public.weekly_dinners%rowtype;
  v_new public.weekly_dinners%rowtype;
begin
  if not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Sem autorização para fechar/reabrir uma quinta-feira.';
  end if;
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

create or replace function public.request_weekly_officer_swap_v1(
  target_club uuid,
  p_dinner uuid,
  p_requested_member uuid,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_requester uuid;
  v_id uuid;
  v_date date;
  v_requester_name text;
begin
  if (select auth.uid()) is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.';
  end if;
  v_requester:=public.current_weekly_officer_member_v1(target_club);
  if v_requester is null then raise exception 'O teu utilizador não está ligado a um membro.'; end if;
  if p_requested_member=v_requester then raise exception 'Não podes pedir troca contigo próprio.'; end if;
  if not exists(select 1 from public.members where id=p_requested_member and club_id=target_club) then
    raise exception 'Membro pedido inválido.';
  end if;

  select d.dinner_date into v_date
  from public.weekly_dinners d
  where d.id=p_dinner and d.club_id=target_club
    and d.dinner_kind='regular' and d.status='planned'
    and d.assigned_member_id=v_requester
    and d.dinner_date>=current_date;
  if v_date is null then raise exception 'Só podes pedir troca do teu próprio jantar futuro.'; end if;

  insert into public.weekly_officer_swap_requests(
    club_id,dinner_id,requester_member_id,requested_member_id,requester_note
  ) values (
    target_club,p_dinner,v_requester,p_requested_member,
    nullif(btrim(coalesce(p_note,'')),'')
  ) returning id into v_id;

  select coalesce(nullif(m.nickname,''),m.full_name) into v_requester_name
  from public.members m where m.id=v_requester;
  perform public.weekly_officer_notify_member_v1(
    target_club,p_requested_member,'Pedido de troca de jantar',
    coalesce(v_requester_name,'Um membro')||' pediu troca para '||to_char(v_date,'DD/MM/YYYY')||'.',
    'weekly_officer_swap',v_id
  );
  perform public.audit_event(
    target_club,'weekly_officer_swap_requested','weekly_officer_swap',
    v_id::text,null,jsonb_build_object('dinner_id',p_dinner,'requested_member_id',p_requested_member),null
  );
  return v_id;
end;
$$;

create or replace function public.respond_weekly_officer_swap_v1(
  target_club uuid,
  p_request uuid,
  p_accept boolean,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_member uuid;
  v_row public.weekly_officer_swap_requests%rowtype;
  v_status text;
  v_responder_name text;
begin
  v_member:=public.current_weekly_officer_member_v1(target_club);
  if v_member is null then raise exception 'O teu utilizador não está ligado a um membro.'; end if;
  select * into v_row from public.weekly_officer_swap_requests
  where id=p_request and club_id=target_club and status='pending' for update;
  if not found then raise exception 'Pedido de troca pendente não encontrado.'; end if;
  if v_row.requested_member_id<>v_member then raise exception 'Este pedido não te é dirigido.'; end if;

  v_status:=case when p_accept then 'accepted' else 'rejected' end;
  update public.weekly_officer_swap_requests
  set status=v_status,response_note=nullif(btrim(coalesce(p_note,'')),''),
      responded_at=now(),responded_by=(select auth.uid()),
      updated_at=now(),updated_by=(select auth.uid())
  where id=p_request;

  select coalesce(nullif(m.nickname,''),m.full_name) into v_responder_name
  from public.members m where m.id=v_member;
  perform public.weekly_officer_notify_member_v1(
    target_club,v_row.requester_member_id,
    case when p_accept then 'Troca aceite' else 'Troca recusada' end,
    coalesce(v_responder_name,'O membro')||
      case when p_accept then ' aceitou o pedido. A alteração aguarda Presidente/Vice-Presidente.' else ' recusou o pedido.' end,
    'weekly_officer_swap',p_request
  );
end;
$$;

create or replace function public.mark_weekly_officer_swap_applied_v1(
  target_club uuid,
  p_request uuid,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_row public.weekly_officer_swap_requests%rowtype;
begin
  if not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Sem autorização para concluir a troca.';
  end if;
  select * into v_row from public.weekly_officer_swap_requests
  where id=p_request and club_id=target_club and status='accepted' for update;
  if not found then raise exception 'Pedido aceite não encontrado.'; end if;

  update public.weekly_officer_swap_requests
  set status='applied',manager_note=nullif(btrim(coalesce(p_note,'')),''),
      applied_at=now(),applied_by=(select auth.uid()),
      updated_at=now(),updated_by=(select auth.uid())
  where id=p_request;

  perform public.weekly_officer_notify_member_v1(
    target_club,v_row.requester_member_id,'Troca concluída',
    'A Direção marcou o pedido de troca como aplicado na escala.',
    'weekly_officer_swap',p_request
  );
  perform public.weekly_officer_notify_member_v1(
    target_club,v_row.requested_member_id,'Troca concluída',
    'A Direção marcou o pedido de troca como aplicado na escala.',
    'weekly_officer_swap',p_request
  );
end;
$$;

create or replace function public.cancel_weekly_officer_swap_v1(
  target_club uuid,
  p_request uuid
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_member uuid;
  v_row public.weekly_officer_swap_requests%rowtype;
begin
  v_member:=public.current_weekly_officer_member_v1(target_club);
  select * into v_row from public.weekly_officer_swap_requests
  where id=p_request and club_id=target_club and status='pending' for update;
  if not found then raise exception 'Pedido pendente não encontrado.'; end if;
  if v_member is distinct from v_row.requester_member_id
     and not public.can_manage_weekly_officer_v1(target_club) then
    raise exception 'Sem autorização para cancelar este pedido.';
  end if;
  update public.weekly_officer_swap_requests
  set status='cancelled',updated_at=now(),updated_by=(select auth.uid())
  where id=p_request;
end;
$$;

-- New members are appended to the end automatically. Existing order is never changed by this trigger.
create or replace function public.weekly_officer_member_append_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order integer;
begin
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

drop trigger if exists trg_weekly_officer_member_append on public.members;
create trigger trg_weekly_officer_member_append
after insert on public.members
for each row execute function public.weekly_officer_member_append_trigger_v1();

-- Seed existing members with the approved initial role priority, then remaining members.
with ranked as (
  select m.club_id,m.id as member_id,
    row_number() over(
      partition by m.club_id
      order by
        case
          when lower(trim(coalesce(m.primary_role,''))) in ('presidente','president') then 10
          when lower(trim(coalesce(m.primary_role,''))) in ('vice-presidente','vice presidente','vice-president','vice president') then 20
          when lower(trim(coalesce(m.primary_role,''))) in ('sargento de armas','sergeant at arms') then 30
          when lower(trim(coalesce(m.primary_role,''))) in ('tesoureiro','treasurer') then 40
          when lower(trim(coalesce(m.primary_role,''))) in ('secretário','secretario','secretary') then 50
          when lower(trim(coalesce(m.primary_role,''))) in ('road captain') then 60
          else 1000
        end,
        m.member_number nulls last,m.created_at,m.id
    )::int as rn
  from public.members m
)
insert into public.weekly_officer_rotation(club_id,member_id,rotation_order)
select club_id,member_id,rn*10 from ranked
on conflict (club_id,member_id) do nothing;

-- RLS: schedule/rotation visible to club members; writes only through RPCs.
alter table public.weekly_officer_rotation enable row level security;
alter table public.weekly_officer_absences enable row level security;
alter table public.weekly_dinners enable row level security;
alter table public.weekly_officer_swap_requests enable row level security;

drop policy if exists weekly_officer_rotation_select on public.weekly_officer_rotation;
create policy weekly_officer_rotation_select on public.weekly_officer_rotation
for select to authenticated using (public.has_club_access(club_id));

drop policy if exists weekly_officer_absences_select on public.weekly_officer_absences;
create policy weekly_officer_absences_select on public.weekly_officer_absences
for select to authenticated using (public.has_club_access(club_id));

drop policy if exists weekly_dinners_select on public.weekly_dinners;
create policy weekly_dinners_select on public.weekly_dinners
for select to authenticated using (public.has_club_access(club_id));

drop policy if exists weekly_officer_swaps_select on public.weekly_officer_swap_requests;
create policy weekly_officer_swaps_select on public.weekly_officer_swap_requests
for select to authenticated using (
  public.can_manage_weekly_officer_v1(club_id)
  or requester_member_id=public.current_weekly_officer_member_v1(club_id)
  or requested_member_id=public.current_weekly_officer_member_v1(club_id)
);

-- No direct client writes.
revoke all on public.weekly_officer_rotation from anon,authenticated;
revoke all on public.weekly_officer_absences from anon,authenticated;
revoke all on public.weekly_dinners from anon,authenticated;
revoke all on public.weekly_officer_swap_requests from anon,authenticated;
grant select on public.weekly_officer_rotation to authenticated;
grant select on public.weekly_officer_absences to authenticated;
grant select on public.weekly_dinners to authenticated;
grant select on public.weekly_officer_swap_requests to authenticated;

-- RPC grants.
revoke execute on function public.can_manage_weekly_officer_v1(uuid) from public,anon;
revoke execute on function public.current_weekly_officer_member_v1(uuid) from public,anon;
revoke execute on function public.weekly_officer_member_available_v1(uuid,uuid,date) from public,anon;
revoke execute on function public.ensure_weekly_officer_schedule_v1(uuid,integer) from public,anon;
revoke execute on function public.set_weekly_officer_member_v1(uuid,uuid,boolean,text,boolean,text) from public,anon;
revoke execute on function public.reorder_weekly_officer_v1(uuid,uuid[]) from public,anon;
revoke execute on function public.save_weekly_officer_absence_v1(uuid,uuid,uuid,text,date,date,text) from public,anon;
revoke execute on function public.delete_weekly_officer_absence_v1(uuid,uuid) from public,anon;
revoke execute on function public.save_weekly_dinner_v1(uuid,uuid,date,uuid,text,text,text,text) from public,anon;
revoke execute on function public.set_weekly_dinner_closed_v1(uuid,uuid,boolean,text) from public,anon;
revoke execute on function public.request_weekly_officer_swap_v1(uuid,uuid,uuid,text) from public,anon;
revoke execute on function public.respond_weekly_officer_swap_v1(uuid,uuid,boolean,text) from public,anon;
revoke execute on function public.mark_weekly_officer_swap_applied_v1(uuid,uuid,text) from public,anon;
revoke execute on function public.cancel_weekly_officer_swap_v1(uuid,uuid) from public,anon;

grant execute on function public.can_manage_weekly_officer_v1(uuid) to authenticated;
grant execute on function public.current_weekly_officer_member_v1(uuid) to authenticated;
grant execute on function public.weekly_officer_member_available_v1(uuid,uuid,date) to authenticated;
grant execute on function public.ensure_weekly_officer_schedule_v1(uuid,integer) to authenticated;
grant execute on function public.set_weekly_officer_member_v1(uuid,uuid,boolean,text,boolean,text) to authenticated;
grant execute on function public.reorder_weekly_officer_v1(uuid,uuid[]) to authenticated;
grant execute on function public.save_weekly_officer_absence_v1(uuid,uuid,uuid,text,date,date,text) to authenticated;
grant execute on function public.delete_weekly_officer_absence_v1(uuid,uuid) to authenticated;
grant execute on function public.save_weekly_dinner_v1(uuid,uuid,date,uuid,text,text,text,text) to authenticated;
grant execute on function public.set_weekly_dinner_closed_v1(uuid,uuid,boolean,text) to authenticated;
grant execute on function public.request_weekly_officer_swap_v1(uuid,uuid,uuid,text) to authenticated;
grant execute on function public.respond_weekly_officer_swap_v1(uuid,uuid,boolean,text) to authenticated;
grant execute on function public.mark_weekly_officer_swap_applied_v1(uuid,uuid,text) to authenticated;
grant execute on function public.cancel_weekly_officer_swap_v1(uuid,uuid) to authenticated;

-- Internal helpers are not API endpoints.
revoke execute on function public.weekly_officer_notify_member_v1(uuid,uuid,text,text,text,uuid) from public,anon,authenticated;
revoke execute on function public.rebuild_weekly_officer_schedule_internal_v1(uuid,date,date) from public,anon,authenticated;
revoke execute on function public.rebuild_weekly_officer_future_internal_v1(uuid,date) from public,anon,authenticated;
revoke execute on function public.weekly_officer_member_append_trigger_v1() from public,anon,authenticated;

-- Ensure timestamp audit columns remain server-stamped for direct trigger-side changes.
create or replace function public.weekly_officer_touch_updated_v1()
returns trigger
language plpgsql
set search_path=public
as $$
begin
  new.updated_at:=now();
  if (select auth.uid()) is not null then new.updated_by:=(select auth.uid()); end if;
  return new;
end;
$$;

drop trigger if exists trg_weekly_officer_rotation_touch on public.weekly_officer_rotation;
create trigger trg_weekly_officer_rotation_touch before update on public.weekly_officer_rotation
for each row execute function public.weekly_officer_touch_updated_v1();
drop trigger if exists trg_weekly_officer_absences_touch on public.weekly_officer_absences;
create trigger trg_weekly_officer_absences_touch before update on public.weekly_officer_absences
for each row execute function public.weekly_officer_touch_updated_v1();
drop trigger if exists trg_weekly_dinners_touch on public.weekly_dinners;
create trigger trg_weekly_dinners_touch before update on public.weekly_dinners
for each row execute function public.weekly_officer_touch_updated_v1();
drop trigger if exists trg_weekly_officer_swaps_touch on public.weekly_officer_swap_requests;
create trigger trg_weekly_officer_swaps_touch before update on public.weekly_officer_swap_requests
for each row execute function public.weekly_officer_touch_updated_v1();

revoke execute on function public.weekly_officer_touch_updated_v1() from public,anon,authenticated;
