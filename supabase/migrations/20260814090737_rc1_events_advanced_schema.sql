alter table public.events
  add column if not exists event_kind text not null default 'general',
  add column if not exists is_private boolean not null default true;

alter table public.events drop constraint if exists events_event_kind_check;
alter table public.events add constraint events_event_kind_check
  check (event_kind in ('general','ride','rock_ride_in'));

create table if not exists public.event_proposals (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  proposed_by uuid not null,
  name text not null,
  description text,
  location text,
  starts_at timestamptz,
  ends_at timestamptz,
  event_kind text not null default 'general' check (event_kind in ('general','ride','rock_ride_in')),
  status text not null default 'submitted' check (status in ('submitted','approved','rejected','withdrawn')),
  decision_notes text,
  decided_by uuid,
  decided_at timestamptz,
  approved_event_id uuid references public.events(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid(),
  constraint event_proposals_dates_check check (ends_at is null or starts_at is null or ends_at >= starts_at)
);

create table if not exists public.event_guests (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid not null references public.events(id) on delete cascade,
  host_member_id uuid not null references public.members(id) on delete cascade,
  registration_id uuid references public.event_registrations(id) on delete set null,
  name text not null,
  status text not null default 'confirmed' check (status in ('confirmed','cancelled','checked_in')),
  checked_in_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid()
);

create table if not exists public.event_routes (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid not null references public.events(id) on delete cascade,
  name text not null default 'Roadbook',
  start_location text,
  end_location text,
  distance_km numeric(10,2) check (distance_km is null or distance_km >= 0),
  estimated_minutes integer check (estimated_minutes is null or estimated_minutes >= 0),
  gpx_path text,
  notes text,
  emergency_notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid(),
  unique (event_id, name)
);

create table if not exists public.event_route_stops (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid not null references public.events(id) on delete cascade,
  route_id uuid not null references public.event_routes(id) on delete cascade,
  sequence_no integer not null check (sequence_no > 0),
  name text not null,
  location text,
  planned_at timestamptz,
  latitude numeric(9,6),
  longitude numeric(9,6),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (route_id, sequence_no)
);

create table if not exists public.event_bands (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid not null references public.events(id) on delete cascade,
  name text not null,
  contact_name text,
  phone text,
  email text,
  slot_start timestamptz,
  slot_end timestamptz,
  agreed_value numeric(12,2) not null default 0 check (agreed_value >= 0),
  paid_value numeric(12,2) not null default 0 check (paid_value >= 0),
  status text not null default 'planned' check (status in ('planned','confirmed','completed','cancelled')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid(),
  constraint event_bands_slot_check check (slot_end is null or slot_start is null or slot_end >= slot_start)
);

create table if not exists public.event_exhibitors (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid not null references public.events(id) on delete cascade,
  name text not null,
  category text,
  contact_name text,
  phone text,
  email text,
  space_label text,
  agreed_value numeric(12,2) not null default 0 check (agreed_value >= 0),
  paid_value numeric(12,2) not null default 0 check (paid_value >= 0),
  status text not null default 'planned' check (status in ('planned','confirmed','completed','cancelled')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid()
);

create table if not exists public.event_sponsors (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid not null references public.events(id) on delete cascade,
  name text not null,
  sponsor_level text,
  contact_name text,
  phone text,
  email text,
  agreed_value numeric(12,2) not null default 0 check (agreed_value >= 0),
  received_value numeric(12,2) not null default 0 check (received_value >= 0),
  status text not null default 'planned' check (status in ('planned','confirmed','completed','cancelled')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid()
);

create table if not exists public.event_octane_configs (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid not null references public.events(id) on delete cascade,
  unit_price numeric(10,2) not null default 1.50 check (unit_price >= 0),
  five_card_units integer not null default 5 check (five_card_units > 0),
  five_card_price numeric(10,2) not null default 7.00 check (five_card_price >= 0),
  ten_card_units integer not null default 10 check (ten_card_units > 0),
  ten_card_price numeric(10,2) not null default 13.00 check (ten_card_price >= 0),
  ten_card_bonus integer not null default 1 check (ten_card_bonus >= 0),
  product_rules jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid(),
  unique (event_id)
);

create table if not exists public.event_tasks (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid not null references public.events(id) on delete cascade,
  title text not null,
  description text,
  priority text not null default 'normal' check (priority in ('low','normal','high','critical')),
  status text not null default 'pending' check (status in ('pending','in_progress','done','cancelled')),
  due_at timestamptz,
  completed_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid()
);

create table if not exists public.event_task_assignees (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid not null references public.events(id) on delete cascade,
  task_id uuid not null references public.event_tasks(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  assigned_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  completed_at timestamptz,
  notes text,
  unique (task_id, member_id)
);

create table if not exists public.event_shifts (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid not null references public.events(id) on delete cascade,
  name text not null,
  area text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  required_people integer not null default 1 check (required_people > 0),
  status text not null default 'planned' check (status in ('planned','active','completed','cancelled')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid(),
  constraint event_shifts_dates_check check (ends_at >= starts_at)
);

create table if not exists public.event_shift_members (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid not null references public.events(id) on delete cascade,
  shift_id uuid not null references public.event_shifts(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  status text not null default 'assigned' check (status in ('assigned','confirmed','present','absent','cancelled')),
  checked_in_at timestamptz,
  checked_out_at timestamptz,
  notes text,
  unique (shift_id, member_id)
);

create table if not exists public.event_program (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid not null references public.events(id) on delete cascade,
  sequence_no integer not null default 1 check (sequence_no > 0),
  title text not null,
  item_type text not null default 'activity',
  starts_at timestamptz,
  ends_at timestamptz,
  location text,
  responsible_member_id uuid references public.members(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_program_dates_check check (ends_at is null or starts_at is null or ends_at >= starts_at),
  unique (event_id, sequence_no)
);

create table if not exists public.event_incidents (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid not null references public.events(id) on delete cascade,
  occurred_at timestamptz not null default now(),
  title text not null,
  description text,
  severity text not null default 'low' check (severity in ('low','medium','high','critical')),
  status text not null default 'open' check (status in ('open','monitoring','resolved','closed')),
  location text,
  reported_by_member_id uuid references public.members(id) on delete set null,
  assigned_member_id uuid references public.members(id) on delete set null,
  resolution text,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid()
);

create index if not exists event_proposals_club_status_idx on public.event_proposals(club_id,status,created_at desc);
create index if not exists event_proposals_proposed_by_idx on public.event_proposals(proposed_by);
create index if not exists event_guests_event_idx on public.event_guests(event_id,status);
create index if not exists event_guests_host_idx on public.event_guests(host_member_id);
create index if not exists event_guests_registration_idx on public.event_guests(registration_id);
create index if not exists event_routes_event_idx on public.event_routes(event_id,active);
create index if not exists event_route_stops_route_idx on public.event_route_stops(route_id,sequence_no);
create index if not exists event_bands_event_idx on public.event_bands(event_id,slot_start);
create index if not exists event_exhibitors_event_idx on public.event_exhibitors(event_id,status);
create index if not exists event_sponsors_event_idx on public.event_sponsors(event_id,status);
create index if not exists event_octane_configs_event_idx on public.event_octane_configs(event_id);
create index if not exists event_tasks_event_idx on public.event_tasks(event_id,status,due_at);
create index if not exists event_task_assignees_task_idx on public.event_task_assignees(task_id);
create index if not exists event_task_assignees_member_idx on public.event_task_assignees(member_id);
create index if not exists event_shifts_event_idx on public.event_shifts(event_id,starts_at);
create index if not exists event_shift_members_shift_idx on public.event_shift_members(shift_id);
create index if not exists event_shift_members_member_idx on public.event_shift_members(member_id);
create index if not exists event_program_event_idx on public.event_program(event_id,sequence_no);
create index if not exists event_program_responsible_idx on public.event_program(responsible_member_id);
create index if not exists event_incidents_event_idx on public.event_incidents(event_id,status,occurred_at desc);
create index if not exists event_incidents_reporter_idx on public.event_incidents(reported_by_member_id);
create index if not exists event_incidents_assigned_idx on public.event_incidents(assigned_member_id);

alter table public.event_proposals enable row level security;
alter table public.event_guests enable row level security;
alter table public.event_routes enable row level security;
alter table public.event_route_stops enable row level security;
alter table public.event_bands enable row level security;
alter table public.event_exhibitors enable row level security;
alter table public.event_sponsors enable row level security;
alter table public.event_octane_configs enable row level security;
alter table public.event_tasks enable row level security;
alter table public.event_task_assignees enable row level security;
alter table public.event_shifts enable row level security;
alter table public.event_shift_members enable row level security;
alter table public.event_program enable row level security;
alter table public.event_incidents enable row level security;

revoke all on table public.event_proposals, public.event_guests, public.event_routes, public.event_route_stops,
  public.event_bands, public.event_exhibitors, public.event_sponsors, public.event_octane_configs,
  public.event_tasks, public.event_task_assignees, public.event_shifts, public.event_shift_members,
  public.event_program, public.event_incidents from anon;

grant select,insert,update,delete on table public.event_proposals, public.event_guests, public.event_routes, public.event_route_stops,
  public.event_bands, public.event_exhibitors, public.event_sponsors, public.event_octane_configs,
  public.event_tasks, public.event_task_assignees, public.event_shifts, public.event_shift_members,
  public.event_program, public.event_incidents to authenticated;