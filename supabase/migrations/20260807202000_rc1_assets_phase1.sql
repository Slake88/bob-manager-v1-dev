alter table public.inventory_assets add column if not exists current_value numeric(12,2) not null default 0;
alter table public.inventory_assets add column if not exists brand text;
alter table public.inventory_assets add column if not exists model text;
alter table public.inventory_assets add column if not exists serial_number text;
alter table public.inventory_assets add column if not exists qr_code text;
alter table public.inventory_assets add column if not exists requires_inspection boolean not null default false;
alter table public.inventory_assets add column if not exists inspection_interval_months integer;
alter table public.inventory_assets add column if not exists last_inspection_at date;
alter table public.inventory_assets add column if not exists next_inspection_at date;
alter table public.inventory_assets add column if not exists custom_attributes jsonb not null default '{}'::jsonb;

alter table public.inventory_assets drop constraint if exists inventory_assets_condition_check;
alter table public.inventory_assets add constraint inventory_assets_condition_check check (condition in ('excellent','good','regular','maintenance','damaged','retired'));
create unique index if not exists inventory_assets_qr_unique on public.inventory_assets(club_id,qr_code) where qr_code is not null;

create table if not exists public.asset_images (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  asset_id uuid not null references public.inventory_assets(id) on delete cascade, storage_path text not null,
  image_type text not null default 'gallery', is_primary boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null, created_at timestamptz not null default now()
);
create table if not exists public.asset_events (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  asset_id uuid not null references public.inventory_assets(id) on delete cascade, event_type text not null,
  title text not null, description text, metadata jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles(id) on delete set null, created_at timestamptz not null default now()
);
create table if not exists public.asset_kits (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  name text not null, description text, active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null, created_at timestamptz not null default now(), unique(club_id,name)
);
create table if not exists public.asset_kit_items (
  kit_id uuid not null references public.asset_kits(id) on delete cascade,
  asset_id uuid not null references public.inventory_assets(id) on delete cascade,
  quantity integer not null default 1 check (quantity > 0), primary key (kit_id,asset_id)
);

alter table public.asset_images enable row level security;
alter table public.asset_events enable row level security;
alter table public.asset_kits enable row level security;
alter table public.asset_kit_items enable row level security;

drop policy if exists asset_images_read on public.asset_images;
create policy asset_images_read on public.asset_images for select to authenticated using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists asset_images_manage on public.asset_images;
create policy asset_images_manage on public.asset_images for all to authenticated using (public.has_club_permission(club_id,'manageAssets')) with check (public.has_club_permission(club_id,'manageAssets'));
drop policy if exists asset_events_read on public.asset_events;
create policy asset_events_read on public.asset_events for select to authenticated using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists asset_events_manage on public.asset_events;
create policy asset_events_manage on public.asset_events for all to authenticated using (public.has_club_permission(club_id,'manageAssets')) with check (public.has_club_permission(club_id,'manageAssets'));
drop policy if exists asset_kits_read on public.asset_kits;
create policy asset_kits_read on public.asset_kits for select to authenticated using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists asset_kits_manage on public.asset_kits;
create policy asset_kits_manage on public.asset_kits for all to authenticated using (public.has_club_permission(club_id,'manageAssets')) with check (public.has_club_permission(club_id,'manageAssets'));
drop policy if exists asset_kit_items_read on public.asset_kit_items;
create policy asset_kit_items_read on public.asset_kit_items for select to authenticated using (exists(select 1 from public.asset_kits k where k.id=kit_id and public.has_club_permission(k.club_id,'viewInventory')));
drop policy if exists asset_kit_items_manage on public.asset_kit_items;
create policy asset_kit_items_manage on public.asset_kit_items for all to authenticated using (exists(select 1 from public.asset_kits k where k.id=kit_id and public.has_club_permission(k.club_id,'manageAssets'))) with check (exists(select 1 from public.asset_kits k where k.id=kit_id and public.has_club_permission(k.club_id,'manageAssets')));

create or replace function public.next_asset_codes_v1(target_club uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_next integer;
begin
  if not public.has_club_permission(target_club,'manageAssets') then raise exception 'Sem autorização para gerir património.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(target_club::text,0));
  select coalesce(max(nullif(regexp_replace(asset_number,'[^0-9]','','g'),'')::integer),0)+1 into v_next
  from public.inventory_assets where club_id=target_club;
  return jsonb_build_object('asset_number','PAT-'||lpad(v_next::text,4,'0'),'qr_code','QR-'||lpad(v_next::text,4,'0'));
end; $$;
grant execute on function public.next_asset_codes_v1(uuid) to authenticated;

create or replace function public.log_asset_event_v1(target_club uuid,p_asset uuid,p_type text,p_title text,p_description text default null,p_metadata jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not public.has_club_permission(target_club,'manageAssets') then raise exception 'Sem autorização para gerir património.'; end if;
  insert into public.asset_events(club_id,asset_id,event_type,title,description,metadata,created_by)
  values(target_club,p_asset,p_type,p_title,p_description,coalesce(p_metadata,'{}'::jsonb),auth.uid()) returning id into v_id;
  return v_id;
end; $$;
grant execute on function public.log_asset_event_v1(uuid,uuid,text,text,text,jsonb) to authenticated;

insert into public.inventory_categories(club_id,area,name)
select c.id,'asset',v.name from public.clubs c cross join (values ('Tendas'),('Geradores'),('Sistema de Som'),('Iluminação'),('Equipamentos Elétricos'),('Ferramentas'),('Cozinha'),('Bar'),('Mobiliário'),('Informática'),('Segurança'),('Outros')) v(name)
on conflict (club_id,area,name) do nothing;
insert into public.inventory_locations(club_id,name)
select c.id,v.name from public.clubs c cross join (values ('Armazém'),('Club House'),('Reboque'),('Garagem'),('Em Evento'),('Emprestado'),('Oficina')) v(name)
on conflict (club_id,name) do nothing;