-- Commit 18: histórico avançado do membro, patches e manutenção de motas

alter table public.member_motorcycles
  add column if not exists active boolean not null default true,
  add column if not exists acquired_on date,
  add column if not exists retired_on date,
  add column if not exists notes text;

create unique index if not exists member_motorcycles_one_primary_active_idx
  on public.member_motorcycles (club_id, member_id)
  where primary_motorcycle = true and active = true;
create index if not exists member_motorcycles_member_active_idx
  on public.member_motorcycles (club_id, member_id, active, created_at desc);
create index if not exists members_club_profile_idx
  on public.members (club_id, profile_id)
  where profile_id is not null;

create table if not exists public.member_status_history (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  old_status text,
  new_status text not null,
  changed_at timestamptz not null default now(),
  changed_by uuid default auth.uid(),
  notes text
);
create index if not exists member_status_history_member_idx
  on public.member_status_history (club_id, member_id, changed_at desc);

create table if not exists public.maintenance_records (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  motorcycle_id uuid not null references public.member_motorcycles(id) on delete cascade,
  service_date date not null default current_date,
  service_type text not null,
  description text,
  odometer_km integer,
  workshop text,
  cost numeric(12,2) not null default 0,
  next_service_date date,
  next_service_km integer,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  constraint maintenance_records_cost_nonnegative check (cost >= 0),
  constraint maintenance_records_odometer_nonnegative check (odometer_km is null or odometer_km >= 0),
  constraint maintenance_records_next_km_nonnegative check (next_service_km is null or next_service_km >= 0)
);
create index if not exists maintenance_records_member_date_idx
  on public.maintenance_records (club_id, member_id, service_date desc);
create index if not exists maintenance_records_motorcycle_date_idx
  on public.maintenance_records (motorcycle_id, service_date desc);

create table if not exists public.maintenance_attachments (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  maintenance_id uuid not null references public.maintenance_records(id) on delete cascade,
  storage_path text not null unique,
  original_file_name text not null,
  mime_type text,
  file_size bigint not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  constraint maintenance_attachments_size_nonnegative check (file_size >= 0)
);
create index if not exists maintenance_attachments_record_idx
  on public.maintenance_attachments (maintenance_id, created_at);

create table if not exists public.member_patch_awards (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  variant_id uuid references public.product_variants(id) on delete restrict,
  patch_name text not null,
  variant_name text,
  status text not null default 'pending',
  requested_at timestamptz not null default now(),
  approved_at timestamptz,
  approved_by uuid,
  delivered_at timestamptz,
  delivered_by uuid,
  inventory_location_id uuid references public.inventory_locations(id) on delete set null,
  delivery_location_name text,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  constraint member_patch_awards_status_check check (status in ('pending','approved','delivered','cancelled'))
);
create index if not exists member_patch_awards_member_idx
  on public.member_patch_awards (club_id, member_id, requested_at desc);
create index if not exists member_patch_awards_status_idx
  on public.member_patch_awards (club_id, status, requested_at);

create table if not exists public.member_timeline (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  event_type text not null,
  title text not null,
  description text,
  event_date date not null default current_date,
  visibility text not null default 'club',
  source_type text,
  source_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  constraint member_timeline_visibility_check check (visibility in ('club','member_private','direction'))
);
create index if not exists member_timeline_member_date_idx
  on public.member_timeline (club_id, member_id, event_date desc, created_at desc);

alter table public.member_status_history enable row level security;
alter table public.maintenance_records enable row level security;
alter table public.maintenance_attachments enable row level security;
alter table public.member_patch_awards enable row level security;
alter table public.member_timeline enable row level security;

revoke all on public.member_status_history from anon, public;
revoke all on public.maintenance_records from anon, public;
revoke all on public.maintenance_attachments from anon, public;
revoke all on public.member_patch_awards from anon, public;
revoke all on public.member_timeline from anon, public;

grant select on public.member_status_history to authenticated;
grant select, insert, update on public.maintenance_records to authenticated;
grant select, insert, delete on public.maintenance_attachments to authenticated;
grant select on public.member_patch_awards to authenticated;
grant select on public.member_timeline to authenticated;
grant all on public.member_status_history, public.maintenance_records,
  public.maintenance_attachments, public.member_patch_awards, public.member_timeline to service_role;

drop policy if exists members_access on public.members;
drop policy if exists club_positions_access on public.club_positions;
drop policy if exists member_positions_access on public.member_positions;

create policy club_positions_read_v2 on public.club_positions
  for select to authenticated using (public.has_club_access(club_id));
create policy club_positions_manage_v2 on public.club_positions
  for all to authenticated
  using (public.has_club_permission(club_id,'manageMembers'))
  with check (public.has_club_permission(club_id,'manageMembers'));

create policy member_positions_read_v2 on public.member_positions
  for select to authenticated using (public.has_club_access(club_id));
create policy member_positions_manage_v2 on public.member_positions
  for all to authenticated
  using (public.has_club_permission(club_id,'manageMembers'))
  with check (public.has_club_permission(club_id,'manageMembers'));

drop policy if exists member_motorcycles_read on public.member_motorcycles;
drop policy if exists member_motorcycles_manage on public.member_motorcycles;
create policy member_motorcycles_read_v2 on public.member_motorcycles
  for select to authenticated
  using (
    public.has_club_permission(club_id,'manageMembers')
    or exists (
      select 1 from public.members m
      where m.id=member_motorcycles.member_id
        and m.club_id=member_motorcycles.club_id
        and m.profile_id=(select auth.uid())
    )
  );
create policy member_motorcycles_manage_v2 on public.member_motorcycles
  for all to authenticated
  using (public.has_club_permission(club_id,'manageMembers'))
  with check (public.has_club_permission(club_id,'manageMembers'));

create policy member_status_history_read on public.member_status_history
  for select to authenticated
  using (
    public.has_club_permission(club_id,'viewMembers')
    or public.has_club_permission(club_id,'manageMembers')
    or exists (
      select 1 from public.members m
      where m.id=member_status_history.member_id
        and m.club_id=member_status_history.club_id
        and m.profile_id=(select auth.uid())
    )
  );

create policy maintenance_records_read on public.maintenance_records
  for select to authenticated
  using (
    public.has_club_permission(club_id,'manageMembers')
    or (
      public.has_club_permission(club_id,'editOwnMemberProfile')
      and exists (
        select 1 from public.members m
        where m.id=maintenance_records.member_id
          and m.club_id=maintenance_records.club_id
          and m.profile_id=(select auth.uid())
      )
    )
  );
create policy maintenance_records_insert on public.maintenance_records
  for insert to authenticated
  with check (
    exists (
      select 1 from public.member_motorcycles mm
      where mm.id=maintenance_records.motorcycle_id
        and mm.club_id=maintenance_records.club_id
        and mm.member_id=maintenance_records.member_id
    )
    and (
      public.has_club_permission(club_id,'manageMembers')
      or (
        public.has_club_permission(club_id,'editOwnMemberProfile')
        and exists (
          select 1 from public.members m
          where m.id=maintenance_records.member_id
            and m.club_id=maintenance_records.club_id
            and m.profile_id=(select auth.uid())
        )
      )
    )
  );
create policy maintenance_records_update on public.maintenance_records
  for update to authenticated
  using (
    public.has_club_permission(club_id,'manageMembers')
    or (
      public.has_club_permission(club_id,'editOwnMemberProfile')
      and exists (
        select 1 from public.members m
        where m.id=maintenance_records.member_id
          and m.club_id=maintenance_records.club_id
          and m.profile_id=(select auth.uid())
      )
    )
  )
  with check (
    exists (
      select 1 from public.member_motorcycles mm
      where mm.id=maintenance_records.motorcycle_id
        and mm.club_id=maintenance_records.club_id
        and mm.member_id=maintenance_records.member_id
    )
    and (
      public.has_club_permission(club_id,'manageMembers')
      or (
        public.has_club_permission(club_id,'editOwnMemberProfile')
        and exists (
          select 1 from public.members m
          where m.id=maintenance_records.member_id
            and m.club_id=maintenance_records.club_id
            and m.profile_id=(select auth.uid())
        )
      )
    )
  );

create policy maintenance_attachments_read on public.maintenance_attachments
  for select to authenticated
  using (
    public.has_club_permission(club_id,'manageMembers')
    or (
      public.has_club_permission(club_id,'editOwnMemberProfile')
      and exists (
        select 1 from public.members m
        where m.id=maintenance_attachments.member_id
          and m.club_id=maintenance_attachments.club_id
          and m.profile_id=(select auth.uid())
      )
    )
  );
create policy maintenance_attachments_insert on public.maintenance_attachments
  for insert to authenticated
  with check (
    exists (
      select 1 from public.maintenance_records r
      where r.id=maintenance_attachments.maintenance_id
        and r.club_id=maintenance_attachments.club_id
        and r.member_id=maintenance_attachments.member_id
    )
    and (
      public.has_club_permission(club_id,'manageMembers')
      or (
        public.has_club_permission(club_id,'editOwnMemberProfile')
        and exists (
          select 1 from public.members m
          where m.id=maintenance_attachments.member_id
            and m.club_id=maintenance_attachments.club_id
            and m.profile_id=(select auth.uid())
        )
      )
    )
  );
create policy maintenance_attachments_delete on public.maintenance_attachments
  for delete to authenticated
  using (
    public.has_club_permission(club_id,'manageMembers')
    or (
      public.has_club_permission(club_id,'editOwnMemberProfile')
      and exists (
        select 1 from public.members m
        where m.id=maintenance_attachments.member_id
          and m.club_id=maintenance_attachments.club_id
          and m.profile_id=(select auth.uid())
      )
    )
  );

create policy member_patch_awards_read on public.member_patch_awards
  for select to authenticated
  using (
    public.has_club_permission(club_id,'viewMembers')
    or public.has_club_permission(club_id,'manageMembers')
    or public.has_club_permission(club_id,'manageInventory')
    or exists (
      select 1 from public.members m
      where m.id=member_patch_awards.member_id
        and m.club_id=member_patch_awards.club_id
        and m.profile_id=(select auth.uid())
    )
  );

create policy member_timeline_read on public.member_timeline
  for select to authenticated
  using (
    public.has_club_permission(club_id,'manageMembers')
    or (visibility='club' and public.has_club_permission(club_id,'viewMembers'))
    or (
      visibility='member_private'
      and exists (
        select 1 from public.members m
        where m.id=member_timeline.member_id
          and m.club_id=member_timeline.club_id
          and m.profile_id=(select auth.uid())
      )
    )
  );

create or replace function public.save_member_motorcycle_v1(
  target_club uuid, p_member uuid, p_motorcycle uuid, p_brand text, p_model text,
  p_year integer, p_registration text, p_nickname text, p_acquired_on date,
  p_notes text, p_primary boolean default false
) returns uuid
language plpgsql security definer set search_path=public
as $$
declare
  v_id uuid;
  v_allowed boolean;
  v_primary boolean:=coalesce(p_primary,false);
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  select exists(
    select 1 from public.members m
    where m.id=p_member and m.club_id=target_club
      and (
        public.has_club_permission(target_club,'manageMembers')
        or (m.profile_id=auth.uid() and public.has_club_permission(target_club,'editOwnMemberProfile'))
      )
  ) into v_allowed;
  if not v_allowed then raise exception 'Sem permissão para gerir as motas deste membro.'; end if;
  if nullif(trim(coalesce(p_brand,'')),'') is null and nullif(trim(coalesce(p_model,'')),'') is null then
    raise exception 'Indica pelo menos a marca ou o modelo da mota.';
  end if;
  if p_year is not null and (p_year<1900 or p_year>extract(year from current_date)::int+1) then
    raise exception 'Ano da mota inválido.';
  end if;

  if p_motorcycle is null then
    if not exists(
      select 1 from public.member_motorcycles
      where club_id=target_club and member_id=p_member and active=true and primary_motorcycle=true
    ) then v_primary:=true; end if;
    if v_primary then
      update public.member_motorcycles
      set primary_motorcycle=false,updated_at=now(),updated_by=auth.uid()
      where club_id=target_club and member_id=p_member and active=true and primary_motorcycle=true;
    end if;
    insert into public.member_motorcycles(
      club_id,member_id,brand,model,year,registration,nickname,primary_motorcycle,
      active,acquired_on,retired_on,notes,created_by,updated_by
    ) values (
      target_club,p_member,nullif(trim(coalesce(p_brand,'')),''),nullif(trim(coalesce(p_model,'')),''),
      p_year,nullif(upper(trim(coalesce(p_registration,''))),''),nullif(trim(coalesce(p_nickname,'')),''),
      v_primary,true,p_acquired_on,null,nullif(trim(coalesce(p_notes,'')),''),auth.uid(),auth.uid()
    ) returning id into v_id;
  else
    select id into v_id from public.member_motorcycles
    where id=p_motorcycle and club_id=target_club and member_id=p_member;
    if v_id is null then raise exception 'Mota não encontrada.'; end if;
    if v_primary then
      update public.member_motorcycles
      set primary_motorcycle=false,updated_at=now(),updated_by=auth.uid()
      where club_id=target_club and member_id=p_member and id<>p_motorcycle
        and active=true and primary_motorcycle=true;
    end if;
    update public.member_motorcycles
    set brand=nullif(trim(coalesce(p_brand,'')),''), model=nullif(trim(coalesce(p_model,'')),''),
        year=p_year, registration=nullif(upper(trim(coalesce(p_registration,''))),''),
        nickname=nullif(trim(coalesce(p_nickname,'')),''), primary_motorcycle=v_primary,
        active=true, acquired_on=p_acquired_on, retired_on=null,
        notes=nullif(trim(coalesce(p_notes,'')),''), updated_at=now(),updated_by=auth.uid()
    where id=p_motorcycle;
  end if;
  return v_id;
end
$$;

create or replace function public.archive_member_motorcycle_v1(
  target_club uuid, p_member uuid, p_motorcycle uuid, p_retired_on date default current_date
) returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_allowed boolean;
  v_was_primary boolean;
  v_next uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  select exists(
    select 1 from public.members m
    where m.id=p_member and m.club_id=target_club
      and (
        public.has_club_permission(target_club,'manageMembers')
        or (m.profile_id=auth.uid() and public.has_club_permission(target_club,'editOwnMemberProfile'))
      )
  ) into v_allowed;
  if not v_allowed then raise exception 'Sem permissão para gerir as motas deste membro.'; end if;
  select primary_motorcycle into v_was_primary
  from public.member_motorcycles
  where id=p_motorcycle and club_id=target_club and member_id=p_member and active=true
  for update;
  if not found then raise exception 'Mota ativa não encontrada.'; end if;
  update public.member_motorcycles
  set active=false,primary_motorcycle=false,retired_on=coalesce(p_retired_on,current_date),
      updated_at=now(),updated_by=auth.uid()
  where id=p_motorcycle;
  if v_was_primary then
    select id into v_next from public.member_motorcycles
    where club_id=target_club and member_id=p_member and active=true
    order by acquired_on desc nulls last,created_at desc limit 1;
    if v_next is not null then
      update public.member_motorcycles
      set primary_motorcycle=true,updated_at=now(),updated_by=auth.uid()
      where id=v_next;
    end if;
  end if;
end
$$;

create or replace function public.member_patch_catalog_v1(target_club uuid)
returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare v_result jsonb;
begin
  if not public.has_club_permission(target_club,'manageMembers') then
    raise exception 'Sem permissão para atribuir patches.';
  end if;
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',p.id,'name',p.name,
      'variants',coalesce((
        select jsonb_agg(jsonb_build_object('id',pv.id,'name',pv.name) order by pv.name)
        from public.product_variants pv where pv.product_id=p.id and pv.active=true
      ),'[]'::jsonb)
    ) order by p.name
  ),'[]'::jsonb)
  into v_result
  from public.products p
  where p.club_id=target_club and p.active=true and p.inventory_area='shop'
    and p.institutional_delivery=true;
  return v_result;
end
$$;

create or replace function public.request_member_patch_v1(
  target_club uuid, p_member uuid, p_product uuid, p_variant uuid default null, p_notes text default null
) returns uuid
language plpgsql security definer set search_path=public
as $$
declare
  v_id uuid;
  v_patch text;
  v_variant text;
begin
  if not public.has_club_permission(target_club,'manageMembers') then
    raise exception 'Sem permissão para atribuir patches.';
  end if;
  if not exists(select 1 from public.members where id=p_member and club_id=target_club) then
    raise exception 'Membro inválido.';
  end if;
  select name into v_patch from public.products
  where id=p_product and club_id=target_club and active=true
    and inventory_area='shop' and institutional_delivery=true;
  if v_patch is null then raise exception 'Patch/artigo institucional inválido.'; end if;
  if exists(select 1 from public.product_variants where product_id=p_product and active=true) and p_variant is null then
    raise exception 'Seleciona a variante do patch.';
  end if;
  if p_variant is not null then
    select name into v_variant from public.product_variants
    where id=p_variant and product_id=p_product and active=true;
    if v_variant is null then raise exception 'Variante inválida.'; end if;
  end if;
  insert into public.member_patch_awards(
    club_id,member_id,product_id,variant_id,patch_name,variant_name,status,notes,created_by,updated_by
  ) values (
    target_club,p_member,p_product,p_variant,v_patch,v_variant,'pending',
    nullif(trim(coalesce(p_notes,'')),''),auth.uid(),auth.uid()
  ) returning id into v_id;
  return v_id;
end
$$;

create or replace function public.approve_member_patch_v1(target_club uuid,p_award uuid)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  if not public.has_club_permission(target_club,'manageMembers') then
    raise exception 'Sem permissão para aprovar patches.';
  end if;
  update public.member_patch_awards
  set status='approved',approved_at=now(),approved_by=auth.uid(),updated_at=now(),updated_by=auth.uid()
  where id=p_award and club_id=target_club and status='pending';
  if not found then raise exception 'Pedido de patch não encontrado ou já processado.'; end if;
end
$$;

create or replace function public.cancel_member_patch_v1(target_club uuid,p_award uuid,p_notes text default null)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  if not public.has_club_permission(target_club,'manageMembers') then
    raise exception 'Sem permissão para cancelar patches.';
  end if;
  update public.member_patch_awards
  set status='cancelled',notes=coalesce(nullif(trim(coalesce(p_notes,'')),''),notes),
      updated_at=now(),updated_by=auth.uid()
  where id=p_award and club_id=target_club and status in ('pending','approved');
  if not found then raise exception 'Pedido de patch não encontrado ou já concluído.'; end if;
end
$$;

create or replace function public.deliver_member_patch_v1(target_club uuid,p_award uuid,p_location uuid)
returns void
language plpgsql security definer set search_path=public
as $$
declare
  a public.member_patch_awards%rowtype;
  v_product public.products%rowtype;
  v_variant public.product_variants%rowtype;
  v_location_name text;
  v_cost numeric:=0;
begin
  if not public.has_club_permission(target_club,'manageInventory') then
    raise exception 'Sem permissão de Inventário para confirmar a entrega.';
  end if;
  select * into a from public.member_patch_awards
  where id=p_award and club_id=target_club and status='approved' for update;
  if not found then raise exception 'Patch não aprovado ou já entregue.'; end if;
  select * into v_product from public.products
  where id=a.product_id and club_id=target_club and active=true for update;
  if not found then raise exception 'Artigo institucional indisponível.'; end if;
  if a.variant_id is not null then
    select * into v_variant from public.product_variants
    where id=a.variant_id and product_id=a.product_id and active=true for update;
    if not found then raise exception 'Variante indisponível.'; end if;
    v_cost:=coalesce(v_variant.cost,v_product.cost,0);
  else
    v_cost:=coalesce(v_product.cost,0);
  end if;
  select name into v_location_name from public.inventory_locations
  where id=p_location and club_id=target_club and active=true;
  if v_location_name is null then raise exception 'Local de inventário inválido.'; end if;

  perform set_config('bob.skip_stock_balance_sync','1',true);
  perform public.inventory_balance_apply_internal_v1(target_club,a.product_id,a.variant_id,p_location,-1,0);
  if a.variant_id is null then
    update public.products p
    set current_stock=(select coalesce(sum(b.quantity),0) from public.inventory_stock_balances b
      where b.club_id=target_club and b.product_id=p.id and b.variant_id is null),
      updated_at=now(),updated_by=auth.uid()
    where p.id=a.product_id and p.club_id=target_club;
  else
    update public.product_variants pv
    set current_stock=(select coalesce(sum(b.quantity),0) from public.inventory_stock_balances b
      where b.club_id=target_club and b.product_id=a.product_id and b.variant_id=pv.id)
    where pv.id=a.variant_id and pv.product_id=a.product_id;
    update public.products p
    set current_stock=(select coalesce(sum(pv.current_stock),0) from public.product_variants pv
      where pv.product_id=p.id and pv.active=true),updated_at=now(),updated_by=auth.uid()
    where p.id=a.product_id and p.club_id=target_club;
  end if;
  perform set_config('bob.skip_stock_balance_sync','0',true);
  insert into public.stock_movements(
    club_id,product_id,variant_id,kind,quantity,unit_cost,notes,created_by,from_location_id
  ) values (
    target_club,a.product_id,a.variant_id,'adjustment',-1,v_cost,
    'Entrega institucional de patch a membro '||a.member_id::text,auth.uid(),p_location
  );
  update public.member_patch_awards
  set status='delivered',delivered_at=now(),delivered_by=auth.uid(),
      inventory_location_id=p_location,delivery_location_name=v_location_name,
      updated_at=now(),updated_by=auth.uid()
  where id=a.id;
end
$$;

create or replace function public.member_timeline_append_v1(
  target_club uuid,p_member uuid,p_event_type text,p_title text,p_description text,
  p_event_date date,p_visibility text,p_source_type text,p_source_id uuid
) returns void
language plpgsql security definer set search_path=public
as $$
begin
  insert into public.member_timeline(
    club_id,member_id,event_type,title,description,event_date,visibility,source_type,source_id,created_by
  ) values (
    target_club,p_member,p_event_type,p_title,nullif(trim(coalesce(p_description,'')),''),
    coalesce(p_event_date,current_date),coalesce(p_visibility,'club'),p_source_type,p_source_id,auth.uid()
  );
end
$$;

create or replace function public.member_status_timeline_trigger_v1()
returns trigger
language plpgsql security definer set search_path=public
as $$
begin
  if tg_op='INSERT' then
    insert into public.member_status_history(club_id,member_id,old_status,new_status,changed_at,changed_by)
    values(new.club_id,new.id,null,new.status,coalesce(new.created_at,now()),auth.uid());
    perform public.member_timeline_append_v1(new.club_id,new.id,'member_created','Membro criado',new.status,coalesce(new.joined_at,current_date),'club','member',new.id);
    if new.prospect_joined_at is not null then
      perform public.member_timeline_append_v1(new.club_id,new.id,'prospect_joined','Entrada como Prospect',null,new.prospect_joined_at,'club','member',new.id);
    end if;
    if new.full_colors_at is not null then
      perform public.member_timeline_append_v1(new.club_id,new.id,'full_colors','Full Colors',null,new.full_colors_at,'club','member',new.id);
    end if;
    return new;
  end if;
  if old.status is distinct from new.status then
    insert into public.member_status_history(club_id,member_id,old_status,new_status,changed_at,changed_by)
    values(new.club_id,new.id,old.status,new.status,now(),auth.uid());
    perform public.member_timeline_append_v1(new.club_id,new.id,'status_change','Estado alterado para '||coalesce(new.status,'—'),'Anterior: '||coalesce(old.status,'—'),current_date,'club','member',new.id);
  end if;
  if old.prospect_joined_at is distinct from new.prospect_joined_at and new.prospect_joined_at is not null then
    perform public.member_timeline_append_v1(new.club_id,new.id,'prospect_joined','Entrada como Prospect',null,new.prospect_joined_at,'club','member',new.id);
  end if;
  if old.full_colors_at is distinct from new.full_colors_at and new.full_colors_at is not null then
    perform public.member_timeline_append_v1(new.club_id,new.id,'full_colors','Full Colors',null,new.full_colors_at,'club','member',new.id);
  end if;
  return new;
end
$$;

create or replace function public.member_position_timeline_trigger_v1()
returns trigger
language plpgsql security definer set search_path=public
as $$
declare v_name text;
begin
  select name into v_name from public.club_positions where id=coalesce(new.position_id,old.position_id);
  if tg_op='INSERT' then
    perform public.member_timeline_append_v1(new.club_id,new.member_id,'position_assigned','Cargo atribuído: '||coalesce(v_name,'Cargo'),null,coalesce(new.starts_at,current_date),'club','member_position',new.id);
    return new;
  end if;
  if old.ends_at is distinct from new.ends_at and new.ends_at is not null then
    perform public.member_timeline_append_v1(new.club_id,new.member_id,'position_ended','Cargo terminado: '||coalesce(v_name,'Cargo'),null,new.ends_at,'club','member_position',new.id);
  end if;
  return new;
end
$$;

create or replace function public.member_motorcycle_timeline_trigger_v1()
returns trigger
language plpgsql security definer set search_path=public
as $$
declare v_label text;
begin
  if tg_op='DELETE' then
    v_label:=trim(coalesce(old.brand,'')||' '||coalesce(old.model,''));
    perform public.member_timeline_append_v1(old.club_id,old.member_id,'motorcycle_removed','Mota removida: '||coalesce(nullif(v_label,''),'Mota'),old.registration,current_date,'member_private','member_motorcycle',old.id);
    return old;
  end if;
  v_label:=trim(coalesce(new.brand,'')||' '||coalesce(new.model,''));
  if tg_op='INSERT' then
    perform public.member_timeline_append_v1(new.club_id,new.member_id,'motorcycle_added','Mota adicionada: '||coalesce(nullif(v_label,''),'Mota'),new.registration,coalesce(new.acquired_on,current_date),'member_private','member_motorcycle',new.id);
  elsif old.active=true and new.active=false then
    perform public.member_timeline_append_v1(new.club_id,new.member_id,'motorcycle_archived','Mota arquivada: '||coalesce(nullif(v_label,''),'Mota'),new.registration,coalesce(new.retired_on,current_date),'member_private','member_motorcycle',new.id);
  elsif old.primary_motorcycle=false and new.primary_motorcycle=true then
    perform public.member_timeline_append_v1(new.club_id,new.member_id,'motorcycle_primary','Nova mota principal: '||coalesce(nullif(v_label,''),'Mota'),new.registration,current_date,'member_private','member_motorcycle',new.id);
  end if;
  return new;
end
$$;

create or replace function public.member_maintenance_timeline_trigger_v1()
returns trigger
language plpgsql security definer set search_path=public
as $$
begin
  perform public.member_timeline_append_v1(new.club_id,new.member_id,'maintenance','Manutenção: '||new.service_type,new.description,new.service_date,'member_private','maintenance_record',new.id);
  return new;
end
$$;

create or replace function public.member_patch_timeline_trigger_v1()
returns trigger
language plpgsql security definer set search_path=public
as $$
declare v_label text;
begin
  v_label:=new.patch_name||case when new.variant_name is null then '' else ' — '||new.variant_name end;
  if tg_op='INSERT' then
    perform public.member_timeline_append_v1(new.club_id,new.member_id,'patch_requested','Patch pendente: '||v_label,new.notes,current_date,'member_private','member_patch_award',new.id);
  elsif old.status is distinct from new.status then
    if new.status='approved' then
      perform public.member_timeline_append_v1(new.club_id,new.member_id,'patch_approved','Patch aprovado: '||v_label,new.notes,current_date,'member_private','member_patch_award',new.id);
    elsif new.status='delivered' then
      perform public.member_timeline_append_v1(new.club_id,new.member_id,'patch_delivered','Patch entregue: '||v_label,new.delivery_location_name,current_date,'club','member_patch_award',new.id);
    elsif new.status='cancelled' then
      perform public.member_timeline_append_v1(new.club_id,new.member_id,'patch_cancelled','Patch cancelado: '||v_label,new.notes,current_date,'member_private','member_patch_award',new.id);
    end if;
  end if;
  return new;
end
$$;

revoke all on function public.save_member_motorcycle_v1(uuid,uuid,uuid,text,text,integer,text,text,date,text,boolean) from public,anon;
revoke all on function public.archive_member_motorcycle_v1(uuid,uuid,uuid,date) from public,anon;
revoke all on function public.member_patch_catalog_v1(uuid) from public,anon;
revoke all on function public.request_member_patch_v1(uuid,uuid,uuid,uuid,text) from public,anon;
revoke all on function public.approve_member_patch_v1(uuid,uuid) from public,anon;
revoke all on function public.cancel_member_patch_v1(uuid,uuid,text) from public,anon;
revoke all on function public.deliver_member_patch_v1(uuid,uuid,uuid) from public,anon;
grant execute on function public.save_member_motorcycle_v1(uuid,uuid,uuid,text,text,integer,text,text,date,text,boolean) to authenticated;
grant execute on function public.archive_member_motorcycle_v1(uuid,uuid,uuid,date) to authenticated;
grant execute on function public.member_patch_catalog_v1(uuid) to authenticated;
grant execute on function public.request_member_patch_v1(uuid,uuid,uuid,uuid,text) to authenticated;
grant execute on function public.approve_member_patch_v1(uuid,uuid) to authenticated;
grant execute on function public.cancel_member_patch_v1(uuid,uuid,text) to authenticated;
grant execute on function public.deliver_member_patch_v1(uuid,uuid,uuid) to authenticated;
revoke all on function public.member_timeline_append_v1(uuid,uuid,text,text,text,date,text,text,uuid) from public,anon,authenticated;
revoke all on function public.member_status_timeline_trigger_v1() from public,anon,authenticated;
revoke all on function public.member_position_timeline_trigger_v1() from public,anon,authenticated;
revoke all on function public.member_motorcycle_timeline_trigger_v1() from public,anon,authenticated;
revoke all on function public.member_maintenance_timeline_trigger_v1() from public,anon,authenticated;
revoke all on function public.member_patch_timeline_trigger_v1() from public,anon,authenticated;

create trigger trg_audit_stamp_maintenance_records before insert or update on public.maintenance_records for each row execute function public.audit_stamp_row_v1();
create trigger trg_audit_capture_maintenance_records after insert or update or delete on public.maintenance_records for each row execute function public.audit_capture_row_v1();
create trigger trg_audit_stamp_maintenance_attachments before insert or update on public.maintenance_attachments for each row execute function public.audit_stamp_row_v1();
create trigger trg_audit_capture_maintenance_attachments after insert or update or delete on public.maintenance_attachments for each row execute function public.audit_capture_row_v1();
create trigger trg_audit_stamp_member_patch_awards before insert or update on public.member_patch_awards for each row execute function public.audit_stamp_row_v1();
create trigger trg_audit_capture_member_patch_awards after insert or update or delete on public.member_patch_awards for each row execute function public.audit_capture_row_v1();
create trigger trg_member_status_timeline after insert or update on public.members for each row execute function public.member_status_timeline_trigger_v1();
create trigger trg_member_position_timeline after insert or update on public.member_positions for each row execute function public.member_position_timeline_trigger_v1();
create trigger trg_member_motorcycle_timeline after insert or update or delete on public.member_motorcycles for each row execute function public.member_motorcycle_timeline_trigger_v1();
create trigger trg_member_maintenance_timeline after insert on public.maintenance_records for each row execute function public.member_maintenance_timeline_trigger_v1();
create trigger trg_member_patch_timeline after insert or update on public.member_patch_awards for each row execute function public.member_patch_timeline_trigger_v1();

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('member-maintenance','member-maintenance',false,15728640,array['application/pdf','image/jpeg','image/png','image/webp']::text[])
on conflict(id) do update set name=excluded.name,public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists member_maintenance_storage_select on storage.objects;
drop policy if exists member_maintenance_storage_insert on storage.objects;
drop policy if exists member_maintenance_storage_delete on storage.objects;
create policy member_maintenance_storage_select on storage.objects
for select to authenticated
using (
  bucket_id='member-maintenance' and split_part(name,'/',2)='members' and split_part(name,'/',4)='maintenance'
  and exists (
    select 1 from public.maintenance_records r
    join public.members m on m.id=r.member_id and m.club_id=r.club_id
    where r.club_id::text=split_part(name,'/',1) and r.member_id::text=split_part(name,'/',3)
      and r.id::text=split_part(name,'/',5)
      and (public.has_club_permission(r.club_id,'manageMembers')
        or (public.has_club_permission(r.club_id,'editOwnMemberProfile') and m.profile_id=(select auth.uid())))
  )
);
create policy member_maintenance_storage_insert on storage.objects
for insert to authenticated
with check (
  bucket_id='member-maintenance' and split_part(name,'/',2)='members' and split_part(name,'/',4)='maintenance'
  and exists (
    select 1 from public.maintenance_records r
    join public.members m on m.id=r.member_id and m.club_id=r.club_id
    where r.club_id::text=split_part(name,'/',1) and r.member_id::text=split_part(name,'/',3)
      and r.id::text=split_part(name,'/',5)
      and (public.has_club_permission(r.club_id,'manageMembers')
        or (public.has_club_permission(r.club_id,'editOwnMemberProfile') and m.profile_id=(select auth.uid())))
  )
);
create policy member_maintenance_storage_delete on storage.objects
for delete to authenticated
using (
  bucket_id='member-maintenance'
  and exists (
    select 1 from public.maintenance_records r
    join public.members m on m.id=r.member_id and m.club_id=r.club_id
    where r.club_id::text=split_part(name,'/',1) and r.member_id::text=split_part(name,'/',3)
      and r.id::text=split_part(name,'/',5)
      and (public.has_club_permission(r.club_id,'manageMembers')
        or (public.has_club_permission(r.club_id,'editOwnMemberProfile') and m.profile_id=(select auth.uid())))
  )
);
