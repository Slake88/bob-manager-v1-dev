create table if not exists public.inventory_count_sessions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  name text not null,
  location_id uuid null references public.inventory_locations(id) on delete set null,
  event_id uuid null references public.events(id) on delete set null,
  status text not null default 'draft' check (status in ('draft','counting','review','completed','cancelled')),
  notes text null,
  started_by uuid not null default auth.uid(),
  started_at timestamptz not null default now(),
  completed_by uuid null,
  completed_at timestamptz null,
  created_at timestamptz not null default now()
);

create table if not exists public.inventory_count_items (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.inventory_count_sessions(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  variant_id uuid null references public.product_variants(id) on delete cascade,
  theoretical_qty numeric not null default 0,
  counted_qty numeric null,
  difference numeric generated always as (coalesce(counted_qty, theoretical_qty) - theoretical_qty) stored,
  unit_cost numeric not null default 0,
  notes text null,
  photo_path text null,
  recounted boolean not null default false,
  counted_by uuid null,
  counted_at timestamptz null,
  unique(session_id, product_id, variant_id)
);

alter table public.inventory_count_sessions enable row level security;
alter table public.inventory_count_items enable row level security;

drop policy if exists inventory_count_sessions_read on public.inventory_count_sessions;
create policy inventory_count_sessions_read on public.inventory_count_sessions for select using (has_club_permission(club_id,'viewInventory'));
drop policy if exists inventory_count_sessions_manage on public.inventory_count_sessions;
create policy inventory_count_sessions_manage on public.inventory_count_sessions for all using (has_club_permission(club_id,'performInventoryCount')) with check (has_club_permission(club_id,'performInventoryCount'));

drop policy if exists inventory_count_items_read on public.inventory_count_items;
create policy inventory_count_items_read on public.inventory_count_items for select using (exists (select 1 from public.inventory_count_sessions s where s.id=session_id and has_club_permission(s.club_id,'viewInventory')));
drop policy if exists inventory_count_items_manage on public.inventory_count_items;
create policy inventory_count_items_manage on public.inventory_count_items for all using (exists (select 1 from public.inventory_count_sessions s where s.id=session_id and has_club_permission(s.club_id,'performInventoryCount'))) with check (exists (select 1 from public.inventory_count_sessions s where s.id=session_id and has_club_permission(s.club_id,'performInventoryCount')));

create index if not exists inventory_count_sessions_club_idx on public.inventory_count_sessions(club_id,created_at desc);
create index if not exists inventory_count_items_session_idx on public.inventory_count_items(session_id);
