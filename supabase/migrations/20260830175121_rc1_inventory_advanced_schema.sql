create table if not exists public.stock_reservations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  variant_id uuid null references public.product_variants(id) on delete restrict,
  location_id uuid not null references public.inventory_locations(id) on delete restrict,
  member_id uuid not null references public.members(id) on delete restrict,
  quantity numeric(12,2) not null check (quantity > 0),
  status text not null default 'active' check (status in ('active','released','cancelled','expired')),
  reserved_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days'),
  released_at timestamptz null,
  released_by uuid null references public.profiles(id) on delete set null,
  release_reason text null,
  notes text null,
  created_by uuid null default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at > reserved_at and expires_at <= reserved_at + interval '30 days')
);
create index if not exists stock_reservations_club_status_expiry_idx on public.stock_reservations(club_id,status,expires_at);
create index if not exists stock_reservations_member_idx on public.stock_reservations(member_id,created_at desc);
create index if not exists stock_reservations_item_location_idx on public.stock_reservations(product_id,variant_id,location_id,status);

create table if not exists public.stock_lots (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  variant_id uuid null references public.product_variants(id) on delete restrict,
  location_id uuid not null references public.inventory_locations(id) on delete restrict,
  lot_code text not null,
  received_at date not null default current_date,
  expires_at date null,
  initial_quantity numeric(12,2) not null check (initial_quantity > 0),
  quantity numeric(12,2) not null check (quantity >= 0),
  unit_cost numeric(12,2) null check (unit_cost is null or unit_cost >= 0),
  supplier text null,
  status text not null default 'active' check (status in ('active','expired','depleted','quarantined')),
  notes text null,
  created_by uuid null default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (quantity <= initial_quantity)
);
create unique index if not exists stock_lots_product_location_code_unique_idx on public.stock_lots(club_id,product_id,location_id,lower(lot_code)) where variant_id is null;
create unique index if not exists stock_lots_variant_location_code_unique_idx on public.stock_lots(club_id,product_id,variant_id,location_id,lower(lot_code)) where variant_id is not null;
create index if not exists stock_lots_expiry_idx on public.stock_lots(club_id,status,expires_at) where expires_at is not null;
create index if not exists stock_lots_item_location_idx on public.stock_lots(product_id,variant_id,location_id,status);

create table if not exists public.stock_breakages (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  variant_id uuid null references public.product_variants(id) on delete restrict,
  location_id uuid not null references public.inventory_locations(id) on delete restrict,
  lot_id uuid null references public.stock_lots(id) on delete set null,
  quantity numeric(12,2) not null check (quantity > 0),
  reason text not null default 'breakage' check (reason in ('breakage','expiry','damage','loss','other')),
  unit_cost numeric(12,2) not null default 0 check (unit_cost >= 0),
  notes text null,
  stock_movement_id uuid null references public.stock_movements(id) on delete set null,
  created_by uuid null default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists stock_breakages_club_created_idx on public.stock_breakages(club_id,created_at desc);
create index if not exists stock_breakages_item_idx on public.stock_breakages(product_id,variant_id,location_id);
create index if not exists stock_breakages_lot_idx on public.stock_breakages(lot_id) where lot_id is not null;
create index if not exists stock_breakages_movement_idx on public.stock_breakages(stock_movement_id) where stock_movement_id is not null;

alter table public.stock_reservations enable row level security;
alter table public.stock_lots enable row level security;
alter table public.stock_breakages enable row level security;

drop policy if exists stock_reservations_read on public.stock_reservations;
create policy stock_reservations_read on public.stock_reservations for select to authenticated using (
  public.has_club_permission(club_id,'manageInventory') or exists (
    select 1 from public.members m where m.id=member_id and m.club_id=club_id and m.profile_id=(select auth.uid())
  )
);
drop policy if exists stock_lots_read on public.stock_lots;
create policy stock_lots_read on public.stock_lots for select to authenticated using (public.has_club_permission(club_id,'manageInventory'));
drop policy if exists stock_breakages_read on public.stock_breakages;
create policy stock_breakages_read on public.stock_breakages for select to authenticated using (public.has_club_permission(club_id,'manageInventory'));

revoke all on table public.stock_reservations from public,anon,authenticated;
revoke all on table public.stock_lots from public,anon,authenticated;
revoke all on table public.stock_breakages from public,anon,authenticated;
grant select on table public.stock_reservations to authenticated;
grant select on table public.stock_lots to authenticated;
grant select on table public.stock_breakages to authenticated;