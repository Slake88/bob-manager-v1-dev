alter table public.products add column if not exists inventory_area text not null default 'shop';
alter table public.products drop constraint if exists products_inventory_area_check;
alter table public.products add constraint products_inventory_area_check check (inventory_area in ('shop','bar'));

create table if not exists public.inventory_categories (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  area text not null check (area in ('shop','bar','asset')), name text not null, active boolean not null default true,
  created_at timestamptz not null default now(), unique(club_id,area,name)
);
create table if not exists public.inventory_locations (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  name text not null, description text, active boolean not null default true, created_at timestamptz not null default now(),
  unique(club_id,name)
);
create table if not exists public.inventory_assets (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  asset_number text, name text not null, category text, description text, acquisition_date date,
  acquisition_value numeric(12,2) not null default 0, supplier text,
  condition text not null default 'good' check (condition in ('excellent','good','maintenance','damaged','retired')),
  location_id uuid references public.inventory_locations(id) on delete set null,
  responsible_member_id uuid references public.members(id) on delete set null,
  photo_path text, warranty_until date, last_maintenance_at date, next_maintenance_at date,
  active boolean not null default true, notes text, created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(club_id,asset_number)
);
create table if not exists public.asset_loans (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  asset_id uuid not null references public.inventory_assets(id) on delete cascade,
  borrower_type text not null default 'member' check (borrower_type in ('member','external','event')),
  member_id uuid references public.members(id) on delete set null, event_id uuid references public.events(id) on delete set null,
  external_name text, loaned_at timestamptz not null default now(), expected_return_at timestamptz, returned_at timestamptz,
  notes text, created_by uuid references public.profiles(id) on delete set null, created_at timestamptz not null default now()
);
create table if not exists public.asset_maintenance (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  asset_id uuid not null references public.inventory_assets(id) on delete cascade, maintenance_date date not null,
  maintenance_type text not null default 'maintenance', description text, cost numeric(12,2) not null default 0,
  supplier text, next_due_date date, created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.inventory_visibility (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  audience text not null check (audience in ('public','prospect','full_color')), allowed boolean not null default true,
  unique(product_id,audience)
);
create table if not exists public.inventory_prices (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  audience text not null check (audience in ('public','prospect','full_color')), price numeric(12,2) not null default 0,
  unique(product_id,audience)
);

alter table public.inventory_categories enable row level security;
alter table public.inventory_locations enable row level security;
alter table public.inventory_assets enable row level security;
alter table public.asset_loans enable row level security;
alter table public.asset_maintenance enable row level security;
alter table public.inventory_visibility enable row level security;
alter table public.inventory_prices enable row level security;

drop policy if exists inventory_categories_read on public.inventory_categories;
create policy inventory_categories_read on public.inventory_categories for select to authenticated using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists inventory_categories_manage on public.inventory_categories;
create policy inventory_categories_manage on public.inventory_categories for all to authenticated using (public.has_club_permission(club_id,'manageInventory')) with check (public.has_club_permission(club_id,'manageInventory'));
drop policy if exists inventory_locations_read on public.inventory_locations;
create policy inventory_locations_read on public.inventory_locations for select to authenticated using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists inventory_locations_manage on public.inventory_locations;
create policy inventory_locations_manage on public.inventory_locations for all to authenticated using (public.has_club_permission(club_id,'manageAssets')) with check (public.has_club_permission(club_id,'manageAssets'));
drop policy if exists inventory_assets_read on public.inventory_assets;
create policy inventory_assets_read on public.inventory_assets for select to authenticated using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists inventory_assets_manage on public.inventory_assets;
create policy inventory_assets_manage on public.inventory_assets for all to authenticated using (public.has_club_permission(club_id,'manageAssets')) with check (public.has_club_permission(club_id,'manageAssets'));
drop policy if exists asset_loans_read on public.asset_loans;
create policy asset_loans_read on public.asset_loans for select to authenticated using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists asset_loans_manage on public.asset_loans;
create policy asset_loans_manage on public.asset_loans for all to authenticated using (public.has_club_permission(club_id,'manageAssets')) with check (public.has_club_permission(club_id,'manageAssets'));
drop policy if exists asset_maintenance_read on public.asset_maintenance;
create policy asset_maintenance_read on public.asset_maintenance for select to authenticated using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists asset_maintenance_manage on public.asset_maintenance;
create policy asset_maintenance_manage on public.asset_maintenance for all to authenticated using (public.has_club_permission(club_id,'manageAssets')) with check (public.has_club_permission(club_id,'manageAssets'));
drop policy if exists inventory_visibility_read on public.inventory_visibility;
create policy inventory_visibility_read on public.inventory_visibility for select to authenticated using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists inventory_visibility_manage on public.inventory_visibility;
create policy inventory_visibility_manage on public.inventory_visibility for all to authenticated using (public.has_club_permission(club_id,'manageMerchandising')) with check (public.has_club_permission(club_id,'manageMerchandising'));
drop policy if exists inventory_prices_read on public.inventory_prices;
create policy inventory_prices_read on public.inventory_prices for select to authenticated using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists inventory_prices_manage on public.inventory_prices;
create policy inventory_prices_manage on public.inventory_prices for all to authenticated using (public.has_club_permission(club_id,'manageMerchandising')) with check (public.has_club_permission(club_id,'manageMerchandising'));

alter table public.club_role_permissions disable trigger trg_activity_role_permissions;
insert into public.club_role_permissions (club_id,role_key,permission_key,allowed,updated_by)
select p.club_id,p.role_key,n.permission_key,p.allowed,p.updated_by
from public.club_role_permissions p
cross join (values ('manageMerchandising'),('manageBar'),('manageAssets'),('performInventoryCount')) n(permission_key)
where p.permission_key='manageInventory'
on conflict (club_id,role_key,permission_key) do nothing;
alter table public.club_role_permissions enable trigger trg_activity_role_permissions;
