-- Clean-rebuild baseline only. Never replay this historical file on an existing application schema.
do $$ begin
 if to_regclass('public.clubs') is not null then
  raise exception '1000 is clean-rebuild only; existing application schema detected' using errcode='55000';
 end if;
end $$;

create extension if not exists pgcrypto;

create extension if not exists citext;


create table if not exists public.schema_migrations_bob (
  version text primary key,
  applied_at timestamptz not null default now(),
  checksum text
);


-- Identidade e acesso: Clube/tenant isolado.
create table if not exists public.clubs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  legal_name text,
  tax_number text,
  slug text,
  logo_path text,
  primary_color text,
  secondary_color text,
  clubhouse_address jsonb,
  timezone text,
  currency text,
  settings jsonb,
  active boolean default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz default now()
);

alter table public.clubs add column if not exists name text;

alter table public.clubs add column if not exists legal_name text;

alter table public.clubs add column if not exists tax_number text;

alter table public.clubs add column if not exists slug text;

alter table public.clubs add column if not exists logo_path text;

alter table public.clubs add column if not exists primary_color text;

alter table public.clubs add column if not exists secondary_color text;

alter table public.clubs add column if not exists clubhouse_address jsonb;

alter table public.clubs add column if not exists timezone text;

alter table public.clubs add column if not exists currency text;

alter table public.clubs add column if not exists settings jsonb;

alter table public.clubs add column if not exists active boolean default true;

alter table public.clubs add column if not exists created_at timestamptz default now();

alter table public.clubs add column if not exists updated_at timestamptz default now();

-- Identidade e acesso: Identidade global ligada a auth.users.
create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text,
  phone text,
  avatar_path text,
  locale text,
  active boolean default true,
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz default now()
);

alter table public.profiles add column if not exists full_name text;

alter table public.profiles add column if not exists email text;

alter table public.profiles add column if not exists phone text;

alter table public.profiles add column if not exists avatar_path text;

alter table public.profiles add column if not exists locale text;

alter table public.profiles add column if not exists active boolean default true;

alter table public.profiles add column if not exists last_login_at timestamptz;

alter table public.profiles add column if not exists created_at timestamptz default now();

alter table public.profiles add column if not exists updated_at timestamptz default now();

-- Identidade e acesso: Associação de utilizador a clube.
create table if not exists public.club_memberships (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  profile_id uuid not null,
  member_id uuid,
  access_role text not null default 'member',
  active boolean not null default true,
  joined_at date,
  ended_at date,
  created_at timestamptz not null default now()
);

alter table public.club_memberships add column if not exists club_id uuid;

alter table public.club_memberships add column if not exists profile_id uuid;

alter table public.club_memberships add column if not exists member_id uuid;

alter table public.club_memberships add column if not exists active boolean default true;

alter table public.club_memberships add column if not exists joined_at date;

alter table public.club_memberships add column if not exists ended_at date;

alter table public.club_memberships add column if not exists created_at timestamptz default now();

create index if not exists idx_club_memberships_club_id on public.club_memberships(club_id);

-- Identidade e acesso: Perfis de acesso configuráveis.
create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  code text,
  name text not null,
  is_system boolean,
  is_direction boolean,
  sort_order integer,
  active boolean default true
);

alter table public.roles add column if not exists club_id uuid;

alter table public.roles add column if not exists code text;

alter table public.roles add column if not exists name text;

alter table public.roles add column if not exists is_system boolean;

alter table public.roles add column if not exists is_direction boolean;

alter table public.roles add column if not exists sort_order integer;

alter table public.roles add column if not exists active boolean default true;

create index if not exists idx_roles_club_id on public.roles(club_id);

-- Identidade e acesso: Catálogo de permissões.
create table if not exists public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text,
  module text,
  action text,
  sensitivity text,
  description text
);

alter table public.permissions add column if not exists code text;

alter table public.permissions add column if not exists module text;

alter table public.permissions add column if not exists action text;

alter table public.permissions add column if not exists sensitivity text;

alter table public.permissions add column if not exists description text;

-- Identidade e acesso: Permissões por role.
create table if not exists public.role_permissions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  role_id uuid,
  permission_id uuid,
  allowed boolean,
  constraints jsonb
);

alter table public.role_permissions add column if not exists club_id uuid;

alter table public.role_permissions add column if not exists role_id uuid;

alter table public.role_permissions add column if not exists permission_id uuid;

alter table public.role_permissions add column if not exists allowed boolean;

alter table public.role_permissions add column if not exists constraints jsonb;

create index if not exists idx_role_permissions_club_id on public.role_permissions(club_id);

-- Identidade e acesso: Vários roles por utilizador no clube.
create table if not exists public.membership_roles (
  id uuid primary key default gen_random_uuid(),
  club_membership_id uuid,
  role_id uuid,
  starts_at timestamptz,
  ends_at timestamptz,
  is_primary boolean
);

alter table public.membership_roles add column if not exists club_membership_id uuid;

alter table public.membership_roles add column if not exists role_id uuid;

alter table public.membership_roles add column if not exists starts_at timestamptz;

alter table public.membership_roles add column if not exists ends_at timestamptz;

alter table public.membership_roles add column if not exists is_primary boolean;

-- Identidade e acesso: Exceções individuais.
-- Match the actual dynamic-permission table declared by 20260807152000.
-- The obsolete membership_id/permission_id/effect model is not recreated.
create table if not exists public.user_permission_overrides (
  club_id uuid not null references public.clubs(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  permission_key text not null,
  allowed boolean not null,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  primary key (club_id, profile_id, permission_key)
);

-- Identidade e acesso: Auditoria específica de permissões.
create table if not exists public.permission_change_log (
  id bigint generated always as identity primary key,
  club_id uuid not null,
  target_profile_id uuid,
  permission_id uuid,
  old_value jsonb,
  new_value jsonb,
  reason text,
  changed_by uuid,
  created_at timestamptz not null default now()
);

alter table public.permission_change_log add column if not exists club_id uuid;

alter table public.permission_change_log add column if not exists target_profile_id uuid;

alter table public.permission_change_log add column if not exists permission_id uuid;

alter table public.permission_change_log add column if not exists old_value jsonb;

alter table public.permission_change_log add column if not exists new_value jsonb;

alter table public.permission_change_log add column if not exists reason text;

alter table public.permission_change_log add column if not exists changed_by uuid;

alter table public.permission_change_log add column if not exists created_at timestamptz default now();

create index if not exists idx_permission_change_log_club_id on public.permission_change_log(club_id);

-- Membros e saúde: Ficha principal do membro.
create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_number integer,
  full_name text not null,
  nickname text,
  tax_number text,
  birth_date date,
  email text,
  phone text,
  address text,
  emergency_contact jsonb,
  status text,
  first_contact_date date,
  prospect_joined_at date,
  full_colors_at date,
  left_at date,
  left_reason text,
  avatar_path text,
  profile_completion numeric(14,2),
  notes text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz default now(),
  archived_at timestamptz
);

alter table public.members add column if not exists club_id uuid;

alter table public.members add column if not exists member_number integer;

alter table public.members add column if not exists full_name text;

alter table public.members add column if not exists nickname text;

alter table public.members add column if not exists tax_number text;

alter table public.members add column if not exists birth_date date;

alter table public.members add column if not exists email text;

alter table public.members add column if not exists phone text;

alter table public.members add column if not exists address text;

alter table public.members add column if not exists status text;

alter table public.members add column if not exists first_contact_date date;

alter table public.members add column if not exists prospect_joined_at date;

alter table public.members add column if not exists full_colors_at date;

alter table public.members add column if not exists left_at date;

alter table public.members add column if not exists left_reason text;

alter table public.members add column if not exists avatar_path text;

alter table public.members add column if not exists profile_completion numeric(14,2);

alter table public.members add column if not exists notes text;

alter table public.members add column if not exists created_by uuid;

alter table public.members add column if not exists created_at timestamptz default now();

alter table public.members add column if not exists updated_at timestamptz default now();

alter table public.members add column if not exists archived_at timestamptz;

create index if not exists idx_members_club_id on public.members(club_id);

-- Membros e saúde: Dados médicos e emergência.
create table if not exists public.member_emergency_data (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  contact_name text,
  relationship text,
  primary_phone text,
  secondary_phone text,
  blood_type text,
  allergies text,
  medication text,
  medical_notes text,
  updated_by uuid,
  updated_at timestamptz default now()
);

alter table public.member_emergency_data add column if not exists club_id uuid;

alter table public.member_emergency_data add column if not exists member_id uuid;

alter table public.member_emergency_data add column if not exists contact_name text;

alter table public.member_emergency_data add column if not exists relationship text;

alter table public.member_emergency_data add column if not exists primary_phone text;

alter table public.member_emergency_data add column if not exists secondary_phone text;

alter table public.member_emergency_data add column if not exists blood_type text;

alter table public.member_emergency_data add column if not exists allergies text;

alter table public.member_emergency_data add column if not exists medication text;

alter table public.member_emergency_data add column if not exists medical_notes text;

alter table public.member_emergency_data add column if not exists updated_by uuid;

alter table public.member_emergency_data add column if not exists updated_at timestamptz default now();

create index if not exists idx_member_emergency_data_club_id on public.member_emergency_data(club_id);

-- Membros e saúde: Histórico de estados.
create table if not exists public.member_status_history (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  status text,
  starts_at date,
  ends_at date,
  reason text,
  changed_by uuid
);

alter table public.member_status_history add column if not exists club_id uuid;

alter table public.member_status_history add column if not exists member_id uuid;

alter table public.member_status_history add column if not exists status text;

alter table public.member_status_history add column if not exists starts_at date;

alter table public.member_status_history add column if not exists ends_at date;

alter table public.member_status_history add column if not exists reason text;

alter table public.member_status_history add column if not exists changed_by uuid;

create index if not exists idx_member_status_history_club_id on public.member_status_history(club_id);

-- Membros e saúde: Cargos tradicionais/configuráveis.
create table if not exists public.club_positions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  code text,
  name text not null,
  hierarchy_level integer,
  is_direction boolean,
  active boolean default true
);

alter table public.club_positions add column if not exists club_id uuid;

alter table public.club_positions add column if not exists code text;

alter table public.club_positions add column if not exists name text;

alter table public.club_positions add column if not exists hierarchy_level integer;

alter table public.club_positions add column if not exists is_direction boolean;

alter table public.club_positions add column if not exists active boolean default true;

create index if not exists idx_club_positions_club_id on public.club_positions(club_id);

-- Membros e saúde: Cargo principal/adicional e histórico.
create table if not exists public.member_positions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  position_id uuid,
  is_primary boolean,
  starts_at date,
  ends_at date,
  appointed_by uuid,
  notes text
);

alter table public.member_positions add column if not exists club_id uuid;

alter table public.member_positions add column if not exists member_id uuid;

alter table public.member_positions add column if not exists position_id uuid;

alter table public.member_positions add column if not exists is_primary boolean;

alter table public.member_positions add column if not exists starts_at date;

alter table public.member_positions add column if not exists ends_at date;

alter table public.member_positions add column if not exists appointed_by uuid;

alter table public.member_positions add column if not exists notes text;

create index if not exists idx_member_positions_club_id on public.member_positions(club_id);

-- Membros e saúde: Patches atribuídos.
create table if not exists public.member_patch_awards (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  patch_product_variant_id uuid,
  patch_type text,
  awarded_at date,
  event_id uuid,
  approved_by uuid,
  delivered_by uuid,
  photo_path text,
  notes text
);

alter table public.member_patch_awards add column if not exists club_id uuid;

alter table public.member_patch_awards add column if not exists member_id uuid;

alter table public.member_patch_awards add column if not exists patch_product_variant_id uuid;

alter table public.member_patch_awards add column if not exists patch_type text;

alter table public.member_patch_awards add column if not exists awarded_at date;

alter table public.member_patch_awards add column if not exists event_id uuid;

alter table public.member_patch_awards add column if not exists approved_by uuid;

alter table public.member_patch_awards add column if not exists delivered_by uuid;

alter table public.member_patch_awards add column if not exists photo_path text;

alter table public.member_patch_awards add column if not exists notes text;

create index if not exists idx_member_patch_awards_club_id on public.member_patch_awards(club_id);

-- Membros e saúde: Material do clube atribuído.
create table if not exists public.assigned_assets (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  product_variant_id uuid,
  serial_number text,
  assigned_at date,
  expected_return_at date,
  returned_at date,
  condition_out text,
  condition_in text,
  status text
);

alter table public.assigned_assets add column if not exists club_id uuid;

alter table public.assigned_assets add column if not exists member_id uuid;

alter table public.assigned_assets add column if not exists product_variant_id uuid;

alter table public.assigned_assets add column if not exists serial_number text;

alter table public.assigned_assets add column if not exists assigned_at date;

alter table public.assigned_assets add column if not exists expected_return_at date;

alter table public.assigned_assets add column if not exists returned_at date;

alter table public.assigned_assets add column if not exists condition_out text;

alter table public.assigned_assets add column if not exists condition_in text;

alter table public.assigned_assets add column if not exists status text;

create index if not exists idx_assigned_assets_club_id on public.assigned_assets(club_id);

-- Membros e saúde: Linha temporal consolidada.
create table if not exists public.member_timeline (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  event_type text,
  event_date timestamptz,
  title text not null,
  description text,
  source_table text,
  source_id uuid,
  visibility text,
  metadata jsonb
);

alter table public.member_timeline add column if not exists club_id uuid;

alter table public.member_timeline add column if not exists member_id uuid;

alter table public.member_timeline add column if not exists event_type text;

alter table public.member_timeline add column if not exists event_date timestamptz;

alter table public.member_timeline add column if not exists title text;

alter table public.member_timeline add column if not exists description text;

alter table public.member_timeline add column if not exists source_table text;

alter table public.member_timeline add column if not exists source_id uuid;

alter table public.member_timeline add column if not exists visibility text;

alter table public.member_timeline add column if not exists metadata jsonb;

create index if not exists idx_member_timeline_club_id on public.member_timeline(club_id);

-- Motas e manutenção: Motas atuais e históricas.
create table if not exists public.motorcycles (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  brand text,
  model text,
  model_year integer,
  registration text,
  engine_cc integer,
  color text,
  vin text,
  purchase_date date,
  sale_date date,
  current_mileage integer,
  is_primary boolean,
  notes text
);

alter table public.motorcycles add column if not exists club_id uuid;

alter table public.motorcycles add column if not exists member_id uuid;

alter table public.motorcycles add column if not exists brand text;

alter table public.motorcycles add column if not exists model text;

alter table public.motorcycles add column if not exists model_year integer;

alter table public.motorcycles add column if not exists registration text;

alter table public.motorcycles add column if not exists engine_cc integer;

alter table public.motorcycles add column if not exists color text;

alter table public.motorcycles add column if not exists vin text;

alter table public.motorcycles add column if not exists purchase_date date;

alter table public.motorcycles add column if not exists sale_date date;

alter table public.motorcycles add column if not exists current_mileage integer;

alter table public.motorcycles add column if not exists is_primary boolean;

alter table public.motorcycles add column if not exists notes text;

create index if not exists idx_motorcycles_club_id on public.motorcycles(club_id);

-- Motas e manutenção: Galeria.
create table if not exists public.motorcycle_photos (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  motorcycle_id uuid,
  storage_path text,
  thumbnail_path text,
  is_primary boolean,
  caption text,
  taken_at date
);

alter table public.motorcycle_photos add column if not exists club_id uuid;

alter table public.motorcycle_photos add column if not exists motorcycle_id uuid;

alter table public.motorcycle_photos add column if not exists storage_path text;

alter table public.motorcycle_photos add column if not exists thumbnail_path text;

alter table public.motorcycle_photos add column if not exists is_primary boolean;

alter table public.motorcycle_photos add column if not exists caption text;

alter table public.motorcycle_photos add column if not exists taken_at date;

create index if not exists idx_motorcycle_photos_club_id on public.motorcycle_photos(club_id);

-- Motas e manutenção: Histórico de propriedade.
create table if not exists public.motorcycle_ownership_history (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  motorcycle_id uuid,
  member_id uuid,
  starts_at date,
  ends_at date,
  notes text
);

alter table public.motorcycle_ownership_history add column if not exists club_id uuid;

alter table public.motorcycle_ownership_history add column if not exists motorcycle_id uuid;

alter table public.motorcycle_ownership_history add column if not exists member_id uuid;

alter table public.motorcycle_ownership_history add column if not exists starts_at date;

alter table public.motorcycle_ownership_history add column if not exists ends_at date;

alter table public.motorcycle_ownership_history add column if not exists notes text;

create index if not exists idx_motorcycle_ownership_history_club_id on public.motorcycle_ownership_history(club_id);

-- Motas e manutenção: Serviços, manutenção e customização.
create table if not exists public.maintenance_records (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  motorcycle_id uuid,
  service_date date,
  mileage integer,
  category text,
  service_type text,
  provider_name text,
  description text,
  parts_cost numeric(12,2),
  labor_cost numeric(12,2),
  other_cost numeric(12,2),
  total_cost numeric(14,2),
  next_service_date date,
  next_service_mileage integer,
  paid_by_club boolean,
  financial_transaction_id uuid,
  notes text
);

alter table public.maintenance_records add column if not exists club_id uuid;

alter table public.maintenance_records add column if not exists motorcycle_id uuid;

alter table public.maintenance_records add column if not exists service_date date;

alter table public.maintenance_records add column if not exists mileage integer;

alter table public.maintenance_records add column if not exists category text;

alter table public.maintenance_records add column if not exists service_type text;

alter table public.maintenance_records add column if not exists provider_name text;

alter table public.maintenance_records add column if not exists description text;

alter table public.maintenance_records add column if not exists parts_cost numeric(12,2);

alter table public.maintenance_records add column if not exists labor_cost numeric(12,2);

alter table public.maintenance_records add column if not exists other_cost numeric(12,2);

alter table public.maintenance_records add column if not exists total_cost numeric(14,2);

alter table public.maintenance_records add column if not exists next_service_date date;

alter table public.maintenance_records add column if not exists next_service_mileage integer;

alter table public.maintenance_records add column if not exists paid_by_club boolean;

alter table public.maintenance_records add column if not exists financial_transaction_id uuid;

alter table public.maintenance_records add column if not exists notes text;

create index if not exists idx_maintenance_records_club_id on public.maintenance_records(club_id);

-- Motas e manutenção: Faturas/fotos por serviço.
create table if not exists public.maintenance_attachments (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  maintenance_record_id uuid,
  attachment_id uuid,
  document_type text
);

alter table public.maintenance_attachments add column if not exists club_id uuid;

alter table public.maintenance_attachments add column if not exists maintenance_record_id uuid;

alter table public.maintenance_attachments add column if not exists attachment_id uuid;

alter table public.maintenance_attachments add column if not exists document_type text;

create index if not exists idx_maintenance_attachments_club_id on public.maintenance_attachments(club_id);

-- Motas e manutenção: Seguro, inspeção e outros.
create table if not exists public.motorcycle_documents (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  motorcycle_id uuid,
  document_id uuid,
  document_type text,
  valid_from date,
  expires_at date
);

alter table public.motorcycle_documents add column if not exists club_id uuid;

alter table public.motorcycle_documents add column if not exists motorcycle_id uuid;

alter table public.motorcycle_documents add column if not exists document_id uuid;

alter table public.motorcycle_documents add column if not exists document_type text;

alter table public.motorcycle_documents add column if not exists valid_from date;

alter table public.motorcycle_documents add column if not exists expires_at date;

create index if not exists idx_motorcycle_documents_club_id on public.motorcycle_documents(club_id);

-- Tesouraria: Local físico do dinheiro.
create table if not exists public.financial_accounts (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  name text not null,
  account_type text,
  bank_name text,
  iban text,
  holder text,
  opening_balance numeric(14,2) default 0,
  opening_date date,
  active boolean default true
);

alter table public.financial_accounts add column if not exists club_id uuid;

alter table public.financial_accounts add column if not exists name text;

alter table public.financial_accounts add column if not exists account_type text;

alter table public.financial_accounts add column if not exists bank_name text;

alter table public.financial_accounts add column if not exists iban text;

alter table public.financial_accounts add column if not exists holder text;

alter table public.financial_accounts add column if not exists opening_balance numeric(14,2) default 0;

alter table public.financial_accounts add column if not exists opening_date date;

alter table public.financial_accounts add column if not exists active boolean default true;

create index if not exists idx_financial_accounts_club_id on public.financial_accounts(club_id);

-- Tesouraria: Finalidade/origem contabilística.
create table if not exists public.funds (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  name text not null,
  code text,
  restricted boolean,
  active boolean default true
);

alter table public.funds add column if not exists club_id uuid;

alter table public.funds add column if not exists name text;

alter table public.funds add column if not exists code text;

alter table public.funds add column if not exists restricted boolean;

alter table public.funds add column if not exists active boolean default true;

create index if not exists idx_funds_club_id on public.funds(club_id);

-- Tesouraria: Centro operacional.
create table if not exists public.cost_centers (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  name text not null,
  parent_id uuid,
  code text,
  active boolean default true
);

alter table public.cost_centers add column if not exists club_id uuid;

alter table public.cost_centers add column if not exists name text;

alter table public.cost_centers add column if not exists parent_id uuid;

alter table public.cost_centers add column if not exists code text;

alter table public.cost_centers add column if not exists active boolean default true;

create index if not exists idx_cost_centers_club_id on public.cost_centers(club_id);

-- Tesouraria: Categorias/subcategorias.
create table if not exists public.financial_categories (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  parent_id uuid,
  kind text,
  name text not null,
  active boolean default true
);

alter table public.financial_categories add column if not exists club_id uuid;

alter table public.financial_categories add column if not exists parent_id uuid;

alter table public.financial_categories add column if not exists kind text;

alter table public.financial_categories add column if not exists name text;

alter table public.financial_categories add column if not exists active boolean default true;

create index if not exists idx_financial_categories_club_id on public.financial_categories(club_id);

-- Tesouraria: Movimento financeiro imutável após confirmação.
create table if not exists public.financial_transactions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  transaction_number text,
  kind text,
  status text,
  transaction_date date,
  account_id uuid,
  destination_account_id uuid,
  fund_id uuid,
  category_id uuid,
  cost_center_id uuid,
  event_id uuid,
  member_id uuid,
  supplier_id uuid,
  description text,
  amount numeric(14,2),
  payment_method_id uuid,
  document_number text,
  reverses_transaction_id uuid,
  confirmed_by uuid,
  confirmed_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now()
);

alter table public.financial_transactions add column if not exists club_id uuid;

alter table public.financial_transactions add column if not exists transaction_number text;

alter table public.financial_transactions add column if not exists kind text;

alter table public.financial_transactions add column if not exists status text;

alter table public.financial_transactions add column if not exists transaction_date date;

alter table public.financial_transactions add column if not exists account_id uuid;

alter table public.financial_transactions add column if not exists destination_account_id uuid;

alter table public.financial_transactions add column if not exists fund_id uuid;

alter table public.financial_transactions add column if not exists category_id uuid;

alter table public.financial_transactions add column if not exists cost_center_id uuid;

alter table public.financial_transactions add column if not exists event_id uuid;

alter table public.financial_transactions add column if not exists member_id uuid;

alter table public.financial_transactions add column if not exists supplier_id uuid;

alter table public.financial_transactions add column if not exists description text;

alter table public.financial_transactions add column if not exists amount numeric(14,2);

alter table public.financial_transactions add column if not exists payment_method_id uuid;

alter table public.financial_transactions add column if not exists document_number text;

alter table public.financial_transactions add column if not exists reverses_transaction_id uuid;

alter table public.financial_transactions add column if not exists confirmed_by uuid;

alter table public.financial_transactions add column if not exists confirmed_at timestamptz;

alter table public.financial_transactions add column if not exists created_by uuid;

alter table public.financial_transactions add column if not exists created_at timestamptz default now();

create index if not exists idx_financial_transactions_club_id on public.financial_transactions(club_id);

-- Tesouraria: Divisão por fundos/centros/categorias.
create table if not exists public.transaction_allocations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  transaction_id uuid,
  fund_id uuid,
  cost_center_id uuid,
  category_id uuid,
  amount numeric(14,2)
);

alter table public.transaction_allocations add column if not exists club_id uuid;

alter table public.transaction_allocations add column if not exists transaction_id uuid;

alter table public.transaction_allocations add column if not exists fund_id uuid;

alter table public.transaction_allocations add column if not exists cost_center_id uuid;

alter table public.transaction_allocations add column if not exists category_id uuid;

alter table public.transaction_allocations add column if not exists amount numeric(14,2);

create index if not exists idx_transaction_allocations_club_id on public.transaction_allocations(club_id);

-- Tesouraria: Fornecedores/entidades.
create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  legal_name text,
  trade_name text,
  tax_number text,
  address jsonb,
  email text,
  phone text,
  iban text,
  category text,
  notes text
);

alter table public.suppliers add column if not exists club_id uuid;

alter table public.suppliers add column if not exists legal_name text;

alter table public.suppliers add column if not exists trade_name text;

alter table public.suppliers add column if not exists tax_number text;

alter table public.suppliers add column if not exists address jsonb;

alter table public.suppliers add column if not exists email text;

alter table public.suppliers add column if not exists phone text;

alter table public.suppliers add column if not exists iban text;

alter table public.suppliers add column if not exists category text;

alter table public.suppliers add column if not exists notes text;

create index if not exists idx_suppliers_club_id on public.suppliers(club_id);

-- Tesouraria: Contas a pagar.
-- payables is created with its real contract by 20260813102933.

-- Tesouraria: Contas a receber.
-- receivables is created with its real contract by 20260813102933.

-- Tesouraria: Despesa submetida por membro.
create table if not exists public.reimbursement_requests (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  requested_by uuid,
  event_id uuid,
  suggested_cost_center_id uuid,
  supplier_name text,
  expense_date date,
  requested_amount numeric(14,2),
  approved_amount numeric(14,2),
  status text,
  reason text,
  reimbursement_method jsonb,
  approved_by uuid,
  financial_transaction_id uuid
);

alter table public.reimbursement_requests add column if not exists club_id uuid;

alter table public.reimbursement_requests add column if not exists requested_by uuid;

alter table public.reimbursement_requests add column if not exists event_id uuid;

alter table public.reimbursement_requests add column if not exists suggested_cost_center_id uuid;

alter table public.reimbursement_requests add column if not exists supplier_name text;

alter table public.reimbursement_requests add column if not exists expense_date date;

alter table public.reimbursement_requests add column if not exists requested_amount numeric(14,2);

alter table public.reimbursement_requests add column if not exists approved_amount numeric(14,2);

alter table public.reimbursement_requests add column if not exists status text;

alter table public.reimbursement_requests add column if not exists reason text;

alter table public.reimbursement_requests add column if not exists reimbursement_method jsonb;

alter table public.reimbursement_requests add column if not exists approved_by uuid;

alter table public.reimbursement_requests add column if not exists financial_transaction_id uuid;

create index if not exists idx_reimbursement_requests_club_id on public.reimbursement_requests(club_id);

-- Tesouraria: Abertura/fecho de caixa.
-- cash_sessions is created with its real contract by 20260813102933.

-- Tesouraria: Reconciliação por período.
-- bank_reconciliations is created with its real contract by 20260813102933.

-- Tesouraria: Orçamentos.
-- budgets is created with its real contract by 20260813102933.

-- Tesouraria: Linhas de orçamento.
-- budget_lines is created with its real contract by 20260813102933.

-- Quotas: Planos configuráveis.
create table if not exists public.fee_plans (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  name text not null,
  frequency text,
  amount numeric(12,2),
  due_day integer,
  destination_fund_id uuid,
  active boolean default true,
  valid_from date,
  valid_until date
);

alter table public.fee_plans add column if not exists club_id uuid;

alter table public.fee_plans add column if not exists name text;

alter table public.fee_plans add column if not exists frequency text;

alter table public.fee_plans add column if not exists amount numeric(14,2);

alter table public.fee_plans add column if not exists due_day integer;

alter table public.fee_plans add column if not exists destination_fund_id uuid;

alter table public.fee_plans add column if not exists active boolean default true;

alter table public.fee_plans add column if not exists valid_from date;

alter table public.fee_plans add column if not exists valid_until date;

create index if not exists idx_fee_plans_club_id on public.fee_plans(club_id);

-- Quotas: Plano por membro e vigência.
create table if not exists public.member_fee_assignments (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  fee_plan_id uuid,
  custom_amount numeric(14,2),
  starts_at date,
  ends_at date,
  status text,
  notes text
);

alter table public.member_fee_assignments add column if not exists club_id uuid;

alter table public.member_fee_assignments add column if not exists member_id uuid;

alter table public.member_fee_assignments add column if not exists fee_plan_id uuid;

alter table public.member_fee_assignments add column if not exists custom_amount numeric(14,2);

alter table public.member_fee_assignments add column if not exists starts_at date;

alter table public.member_fee_assignments add column if not exists ends_at date;

alter table public.member_fee_assignments add column if not exists status text;

alter table public.member_fee_assignments add column if not exists notes text;

create index if not exists idx_member_fee_assignments_club_id on public.member_fee_assignments(club_id);

-- Quotas: Obrigação por período.
create table if not exists public.fee_obligations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  fee_plan_id uuid,
  period_start date,
  period_end date,
  due_date date,
  amount numeric(12,2),
  paid_amount numeric(12,2) default 0,
  status text,
  source text,
  unique_key text
);

alter table public.fee_obligations add column if not exists club_id uuid;

alter table public.fee_obligations add column if not exists member_id uuid;

alter table public.fee_obligations add column if not exists fee_plan_id uuid;

alter table public.fee_obligations add column if not exists period_start date;

alter table public.fee_obligations add column if not exists period_end date;

alter table public.fee_obligations add column if not exists due_date date;

alter table public.fee_obligations add column if not exists amount numeric(14,2);

alter table public.fee_obligations add column if not exists paid_amount numeric(14,2) default 0;

alter table public.fee_obligations add column if not exists status text;

alter table public.fee_obligations add column if not exists source text;

alter table public.fee_obligations add column if not exists unique_key text;

create index if not exists idx_fee_obligations_club_id on public.fee_obligations(club_id);

-- Quotas: Pagamento recebido/validado.
create table if not exists public.fee_payments (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  payment_date date,
  amount numeric(12,2),
  account_id uuid,
  fund_id uuid,
  method_id uuid,
  status text,
  reported_payment_id uuid,
  transaction_id uuid,
  receipt_id uuid
);

alter table public.fee_payments add column if not exists club_id uuid;

alter table public.fee_payments add column if not exists member_id uuid;

alter table public.fee_payments add column if not exists payment_date date;

alter table public.fee_payments add column if not exists amount numeric(14,2);

alter table public.fee_payments add column if not exists account_id uuid;

alter table public.fee_payments add column if not exists fund_id uuid;

alter table public.fee_payments add column if not exists method_id uuid;

alter table public.fee_payments add column if not exists status text;

alter table public.fee_payments add column if not exists reported_payment_id uuid;

alter table public.fee_payments add column if not exists transaction_id uuid;

alter table public.fee_payments add column if not exists receipt_id uuid;

create index if not exists idx_fee_payments_club_id on public.fee_payments(club_id);

-- Quotas: Aplicação a obrigações.
create table if not exists public.fee_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  fee_payment_id uuid,
  fee_obligation_id uuid,
  amount numeric(12,2)
);

alter table public.fee_payment_allocations add column if not exists club_id uuid;

alter table public.fee_payment_allocations add column if not exists fee_payment_id uuid;

alter table public.fee_payment_allocations add column if not exists fee_obligation_id uuid;

alter table public.fee_payment_allocations add column if not exists amount numeric(14,2);

create index if not exists idx_fee_payment_allocations_club_id on public.fee_payment_allocations(club_id);

-- Quotas: Crédito do membro.
-- Canonical fee writer contract from 20260813151110; CREATE IF NOT EXISTS later cannot repair a pre-created table.
create table if not exists public.fee_credits(
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete restrict,
  amount numeric(12,2) not null check(amount<>0),
  entry_type text not null check(entry_type in ('payment_excess','manual_adjustment','application','reversal')),
  payment_id uuid references public.fee_payments(id) on delete restrict,
  obligation_id uuid references public.fee_obligations(id) on delete restrict,
  source_credit_id uuid references public.fee_credits(id) on delete restrict,
  reversal_of uuid references public.fee_credits(id) on delete restrict,
  reason text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

alter table public.fee_credits add column if not exists club_id uuid;

alter table public.fee_credits add column if not exists member_id uuid;

alter table public.fee_credits add column if not exists origin_payment_id uuid;

alter table public.fee_credits add column if not exists amount numeric(14,2);

alter table public.fee_credits add column if not exists remaining_amount numeric(14,2);

alter table public.fee_credits add column if not exists status text;

alter table public.fee_credits add column if not exists created_at timestamptz default now();

create index if not exists idx_fee_credits_club_id on public.fee_credits(club_id);

-- Quotas: Isenções.
-- Canonical fee writer contract from 20260813151110; CREATE IF NOT EXISTS later cannot repair a pre-created table.
create table if not exists public.fee_exemptions(
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete restrict,
  obligation_id uuid not null references public.fee_obligations(id) on delete restrict,
  amount numeric(12,2) not null check(amount>0),
  reason text not null,
  status text not null default 'active' check(status in ('active','reversed')),
  reversed_at timestamptz,
  reversed_by uuid,
  reversal_reason text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

alter table public.fee_exemptions add column if not exists club_id uuid;

alter table public.fee_exemptions add column if not exists member_id uuid;

alter table public.fee_exemptions add column if not exists starts_at date;

alter table public.fee_exemptions add column if not exists ends_at date;

alter table public.fee_exemptions add column if not exists type text;

alter table public.fee_exemptions add column if not exists value numeric(14,2);

alter table public.fee_exemptions add column if not exists reason text;

alter table public.fee_exemptions add column if not exists approved_by uuid;

create index if not exists idx_fee_exemptions_club_id on public.fee_exemptions(club_id);

-- Quotas: Dívida inicial, perdão e correções.
-- Canonical fee writer contract from 20260813151110; CREATE IF NOT EXISTS later cannot repair a pre-created table.
create table if not exists public.fee_adjustments(
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete restrict,
  obligation_id uuid not null references public.fee_obligations(id) on delete restrict,
  amount numeric(12,2) not null check(amount<>0),
  reason text not null,
  status text not null default 'active' check(status in ('active','reversed')),
  reversed_at timestamptz,
  reversed_by uuid,
  reversal_reason text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

alter table public.fee_adjustments add column if not exists club_id uuid;

alter table public.fee_adjustments add column if not exists member_id uuid;

alter table public.fee_adjustments add column if not exists obligation_id uuid;

alter table public.fee_adjustments add column if not exists adjustment_type text;

alter table public.fee_adjustments add column if not exists amount numeric(14,2);

alter table public.fee_adjustments add column if not exists reason text;

alter table public.fee_adjustments add column if not exists approved_by uuid;

alter table public.fee_adjustments add column if not exists created_at timestamptz default now();

create index if not exists idx_fee_adjustments_club_id on public.fee_adjustments(club_id);

-- Quotas: Comprovativos.
create table if not exists public.fee_receipts (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  receipt_number text,
  fee_payment_id uuid,
  pdf_path text,
  qr_token uuid,
  status text,
  issued_at timestamptz
);

alter table public.fee_receipts add column if not exists club_id uuid;

alter table public.fee_receipts add column if not exists receipt_number text;

alter table public.fee_receipts add column if not exists fee_payment_id uuid;

alter table public.fee_receipts add column if not exists pdf_path text;

alter table public.fee_receipts add column if not exists qr_token uuid;

alter table public.fee_receipts add column if not exists status text;

alter table public.fee_receipts add column if not exists issued_at timestamptz;

create index if not exists idx_fee_receipts_club_id on public.fee_receipts(club_id);

-- Quotas: Pagamento comunicado pelo membro.
-- Canonical reported-payment writer and review contract, same operational schema.
create table if not exists public.reported_payments(
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete restrict,
  amount numeric(12,2) not null check(amount>0),
  paid_on date not null,
  payment_method text not null,
  notes text,
  proof_path text not null,
  proof_name text not null,
  proof_mime_type text,
  proof_size bigint check(proof_size is null or proof_size>=0),
  status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled','reversed')),
  review_notes text,
  reviewed_at timestamptz,
  reviewed_by uuid,
  fee_payment_id uuid references public.fee_payments(id) on delete restrict,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

alter table public.reported_payments add column if not exists club_id uuid;

alter table public.reported_payments add column if not exists member_id uuid;

alter table public.reported_payments add column if not exists amount numeric(14,2);

alter table public.reported_payments add column if not exists payment_date date;

alter table public.reported_payments add column if not exists method_id uuid;

alter table public.reported_payments add column if not exists reference text;

alter table public.reported_payments add column if not exists intended_periods jsonb;

alter table public.reported_payments add column if not exists status text;

alter table public.reported_payments add column if not exists attachment_id uuid;

alter table public.reported_payments add column if not exists validated_by uuid;

alter table public.reported_payments add column if not exists validation_notes text;

create index if not exists idx_reported_payments_club_id on public.reported_payments(club_id);

-- Quotas: Inscrição inicial manual.
create table if not exists public.prospect_enrollment_fees (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  amount numeric(14,2),
  charged_at date,
  payment_id uuid,
  status text
);

alter table public.prospect_enrollment_fees add column if not exists club_id uuid;

alter table public.prospect_enrollment_fees add column if not exists member_id uuid;

alter table public.prospect_enrollment_fees add column if not exists amount numeric(14,2);

alter table public.prospect_enrollment_fees add column if not exists charged_at date;

alter table public.prospect_enrollment_fees add column if not exists payment_id uuid;

alter table public.prospect_enrollment_fees add column if not exists status text;

create index if not exists idx_prospect_enrollment_fees_club_id on public.prospect_enrollment_fees(club_id);

-- Euromilhões: Grupo de participação.
create table if not exists public.lottery_groups (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  name text not null,
  billing_frequency text,
  participant_amount numeric(14,2),
  fund_id uuid,
  account_id uuid,
  responsible_profile_id uuid,
  active boolean default true,
  rules jsonb
);

alter table public.lottery_groups add column if not exists club_id uuid;

alter table public.lottery_groups add column if not exists name text;

alter table public.lottery_groups add column if not exists billing_frequency text;

alter table public.lottery_groups add column if not exists participant_amount numeric(14,2);

alter table public.lottery_groups add column if not exists fund_id uuid;

alter table public.lottery_groups add column if not exists account_id uuid;

alter table public.lottery_groups add column if not exists responsible_profile_id uuid;

alter table public.lottery_groups add column if not exists active boolean default true;

alter table public.lottery_groups add column if not exists rules jsonb;

create index if not exists idx_lottery_groups_club_id on public.lottery_groups(club_id);

-- Euromilhões: Participantes membros/externos.
create table if not exists public.lottery_participants (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  group_id uuid,
  member_id uuid,
  external_person jsonb,
  starts_at date,
  ends_at date,
  status text,
  custom_amount numeric(14,2)
);

alter table public.lottery_participants add column if not exists club_id uuid;

alter table public.lottery_participants add column if not exists group_id uuid;

alter table public.lottery_participants add column if not exists member_id uuid;

alter table public.lottery_participants add column if not exists external_person jsonb;

alter table public.lottery_participants add column if not exists starts_at date;

alter table public.lottery_participants add column if not exists ends_at date;

alter table public.lottery_participants add column if not exists status text;

alter table public.lottery_participants add column if not exists custom_amount numeric(14,2);

create index if not exists idx_lottery_participants_club_id on public.lottery_participants(club_id);

-- Euromilhões: Chave completa por participante.
create table if not exists public.participant_keys (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  participant_id uuid,
  numbers smallint[],
  stars smallint[],
  valid_from date,
  valid_until date,
  active boolean default true
);

alter table public.participant_keys add column if not exists club_id uuid;

alter table public.participant_keys add column if not exists participant_id uuid;

alter table public.participant_keys add column if not exists numbers smallint[];

alter table public.participant_keys add column if not exists stars smallint[];

alter table public.participant_keys add column if not exists valid_from date;

alter table public.participant_keys add column if not exists valid_until date;

alter table public.participant_keys add column if not exists active boolean default true;

create index if not exists idx_participant_keys_club_id on public.participant_keys(club_id);

-- Euromilhões: Semana/mês de cobrança.
create table if not exists public.lottery_periods (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  group_id uuid,
  period_start date,
  period_end date,
  status text,
  participant_amount numeric(14,2),
  expected_amount numeric(14,2),
  received_amount numeric(14,2)
);

alter table public.lottery_periods add column if not exists club_id uuid;

alter table public.lottery_periods add column if not exists group_id uuid;

alter table public.lottery_periods add column if not exists period_start date;

alter table public.lottery_periods add column if not exists period_end date;

alter table public.lottery_periods add column if not exists status text;

alter table public.lottery_periods add column if not exists participant_amount numeric(14,2);

alter table public.lottery_periods add column if not exists expected_amount numeric(14,2);

alter table public.lottery_periods add column if not exists received_amount numeric(14,2);

create index if not exists idx_lottery_periods_club_id on public.lottery_periods(club_id);

-- Euromilhões: Obrigação e pagamento por participante/período.
create table if not exists public.lottery_contributions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  period_id uuid,
  participant_id uuid,
  amount_due numeric(14,2),
  amount_paid numeric(14,2),
  status text,
  credit numeric(14,2)
);

alter table public.lottery_contributions add column if not exists club_id uuid;

alter table public.lottery_contributions add column if not exists period_id uuid;

alter table public.lottery_contributions add column if not exists participant_id uuid;

alter table public.lottery_contributions add column if not exists amount_due numeric(14,2);

alter table public.lottery_contributions add column if not exists amount_paid numeric(14,2);

alter table public.lottery_contributions add column if not exists status text;

alter table public.lottery_contributions add column if not exists credit numeric(14,2);

create index if not exists idx_lottery_contributions_club_id on public.lottery_contributions(club_id);

-- Euromilhões: Dois sorteios semanais.
create table if not exists public.lottery_draws (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  period_id uuid,
  draw_date date,
  draw_number text,
  status text,
  source_url text,
  imported_at timestamptz,
  confirmed_by uuid
);

alter table public.lottery_draws add column if not exists club_id uuid;

alter table public.lottery_draws add column if not exists period_id uuid;

alter table public.lottery_draws add column if not exists draw_date date;

alter table public.lottery_draws add column if not exists draw_number text;

alter table public.lottery_draws add column if not exists status text;

alter table public.lottery_draws add column if not exists source_url text;

alter table public.lottery_draws add column if not exists imported_at timestamptz;

alter table public.lottery_draws add column if not exists confirmed_by uuid;

create index if not exists idx_lottery_draws_club_id on public.lottery_draws(club_id);

-- Euromilhões: Aposta e comprovativo.
create table if not exists public.lottery_bets (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  draw_id uuid,
  cost numeric(14,2),
  receipt_document_id uuid,
  status text,
  submitted_at timestamptz
);

alter table public.lottery_bets add column if not exists club_id uuid;

alter table public.lottery_bets add column if not exists draw_id uuid;

alter table public.lottery_bets add column if not exists cost numeric(14,2);

alter table public.lottery_bets add column if not exists receipt_document_id uuid;

alter table public.lottery_bets add column if not exists status text;

alter table public.lottery_bets add column if not exists submitted_at timestamptz;

create index if not exists idx_lottery_bets_club_id on public.lottery_bets(club_id);

-- Euromilhões: Snapshot das chaves jogadas.
create table if not exists public.lottery_bet_keys (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  bet_id uuid,
  participant_id uuid,
  participant_key_id uuid,
  numbers smallint[],
  stars smallint[]
);

alter table public.lottery_bet_keys add column if not exists club_id uuid;

alter table public.lottery_bet_keys add column if not exists bet_id uuid;

alter table public.lottery_bet_keys add column if not exists participant_id uuid;

alter table public.lottery_bet_keys add column if not exists participant_key_id uuid;

alter table public.lottery_bet_keys add column if not exists numbers smallint[];

alter table public.lottery_bet_keys add column if not exists stars smallint[];

create index if not exists idx_lottery_bet_keys_club_id on public.lottery_bet_keys(club_id);

-- Euromilhões: Resultado oficial/importado.
create table if not exists public.lottery_results (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  draw_id uuid,
  numbers smallint[],
  stars smallint[],
  prize_table jsonb,
  status text,
  confirmed_at timestamptz
);

alter table public.lottery_results add column if not exists club_id uuid;

alter table public.lottery_results add column if not exists draw_id uuid;

alter table public.lottery_results add column if not exists numbers smallint[];

alter table public.lottery_results add column if not exists stars smallint[];

alter table public.lottery_results add column if not exists prize_table jsonb;

alter table public.lottery_results add column if not exists status text;

alter table public.lottery_results add column if not exists confirmed_at timestamptz;

create index if not exists idx_lottery_results_club_id on public.lottery_results(club_id);

-- Euromilhões: Acertos por participante.
create table if not exists public.lottery_matches (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  result_id uuid,
  participant_id uuid,
  bet_key_id uuid,
  matched_numbers text,
  matched_stars text,
  prize_category text,
  estimated_prize numeric(14,2)
);

alter table public.lottery_matches add column if not exists club_id uuid;

alter table public.lottery_matches add column if not exists result_id uuid;

alter table public.lottery_matches add column if not exists participant_id uuid;

alter table public.lottery_matches add column if not exists bet_key_id uuid;

alter table public.lottery_matches add column if not exists matched_numbers text;

alter table public.lottery_matches add column if not exists matched_stars text;

alter table public.lottery_matches add column if not exists prize_category text;

alter table public.lottery_matches add column if not exists estimated_prize numeric(14,2);

create index if not exists idx_lottery_matches_club_id on public.lottery_matches(club_id);

-- Euromilhões: Prémios recebidos.
create table if not exists public.lottery_prizes (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  draw_id uuid,
  amount numeric(14,2),
  received_at date,
  transaction_id uuid,
  document_id uuid
);

alter table public.lottery_prizes add column if not exists club_id uuid;

alter table public.lottery_prizes add column if not exists draw_id uuid;

alter table public.lottery_prizes add column if not exists amount numeric(14,2);

alter table public.lottery_prizes add column if not exists received_at date;

alter table public.lottery_prizes add column if not exists transaction_id uuid;

alter table public.lottery_prizes add column if not exists document_id uuid;

create index if not exists idx_lottery_prizes_club_id on public.lottery_prizes(club_id);

-- Euromilhões: Utilização aprovada de prémios/saldo.
create table if not exists public.lottery_fund_uses (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  group_id uuid,
  amount numeric(14,2),
  purpose text,
  destination_fund_id uuid,
  event_id uuid,
  status text,
  approved_by uuid,
  transaction_id uuid
);

alter table public.lottery_fund_uses add column if not exists club_id uuid;

alter table public.lottery_fund_uses add column if not exists group_id uuid;

alter table public.lottery_fund_uses add column if not exists amount numeric(14,2);

alter table public.lottery_fund_uses add column if not exists purpose text;

alter table public.lottery_fund_uses add column if not exists destination_fund_id uuid;

alter table public.lottery_fund_uses add column if not exists event_id uuid;

alter table public.lottery_fund_uses add column if not exists status text;

alter table public.lottery_fund_uses add column if not exists approved_by uuid;

alter table public.lottery_fund_uses add column if not exists transaction_id uuid;

create index if not exists idx_lottery_fund_uses_club_id on public.lottery_fund_uses(club_id);

-- Eventos: Evento oficial.
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_type text,
  name text not null,
  short_name text,
  edition text,
  description text,
  cover_path text,
  starts_at timestamptz,
  ends_at timestamptz,
  location text,
  visibility text,
  capacity integer,
  expected_attendance integer,
  entry_type text,
  status text,
  is_rock_ride_template boolean,
  created_by uuid
);

alter table public.events add column if not exists club_id uuid;

alter table public.events add column if not exists event_type text;

alter table public.events add column if not exists name text;

alter table public.events add column if not exists short_name text;

alter table public.events add column if not exists edition text;

alter table public.events add column if not exists description text;

alter table public.events add column if not exists cover_path text;

alter table public.events add column if not exists starts_at timestamptz;

alter table public.events add column if not exists ends_at timestamptz;

alter table public.events add column if not exists location text;

alter table public.events add column if not exists visibility text;

alter table public.events add column if not exists capacity integer;

alter table public.events add column if not exists expected_attendance integer;

alter table public.events add column if not exists entry_type text;

alter table public.events add column if not exists status text;

alter table public.events add column if not exists is_rock_ride_template boolean;

alter table public.events add column if not exists created_by uuid;

create index if not exists idx_events_club_id on public.events(club_id);

-- Eventos: Propostas por membros.
create table if not exists public.event_proposals (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  proposed_by uuid,
  payload jsonb,
  status text,
  reviewed_by uuid,
  review_notes text,
  event_id uuid
);

alter table public.event_proposals add column if not exists club_id uuid;

alter table public.event_proposals add column if not exists proposed_by uuid;

alter table public.event_proposals add column if not exists payload jsonb;

alter table public.event_proposals add column if not exists status text;

alter table public.event_proposals add column if not exists reviewed_by uuid;

alter table public.event_proposals add column if not exists review_notes text;

alter table public.event_proposals add column if not exists event_id uuid;

create index if not exists idx_event_proposals_club_id on public.event_proposals(club_id);

-- Eventos: Participação de membros.
create table if not exists public.event_participants (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid,
  member_id uuid,
  status text,
  attending_by_motorcycle boolean,
  motorcycle_id uuid,
  checked_in_at timestamptz,
  notes text
);

alter table public.event_participants add column if not exists club_id uuid;

alter table public.event_participants add column if not exists event_id uuid;

alter table public.event_participants add column if not exists member_id uuid;

alter table public.event_participants add column if not exists status text;

alter table public.event_participants add column if not exists attending_by_motorcycle boolean;

alter table public.event_participants add column if not exists motorcycle_id uuid;

alter table public.event_participants add column if not exists checked_in_at timestamptz;

alter table public.event_participants add column if not exists notes text;

create index if not exists idx_event_participants_club_id on public.event_participants(club_id);

-- Eventos: Acompanhantes/visitantes.
create table if not exists public.event_guests (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid,
  host_member_id uuid,
  name text not null,
  phone text,
  status text,
  payment_status text,
  notes text
);

alter table public.event_guests add column if not exists club_id uuid;

alter table public.event_guests add column if not exists event_id uuid;

alter table public.event_guests add column if not exists host_member_id uuid;

alter table public.event_guests add column if not exists name text;

alter table public.event_guests add column if not exists phone text;

alter table public.event_guests add column if not exists status text;

alter table public.event_guests add column if not exists payment_status text;

alter table public.event_guests add column if not exists notes text;

create index if not exists idx_event_guests_club_id on public.event_guests(club_id);

-- Eventos: Tarefas.
create table if not exists public.event_tasks (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid,
  title text not null,
  description text,
  area text,
  priority text,
  status text,
  starts_at timestamptz,
  due_at timestamptz,
  progress integer,
  parent_task_id uuid
);

alter table public.event_tasks add column if not exists club_id uuid;

alter table public.event_tasks add column if not exists event_id uuid;

alter table public.event_tasks add column if not exists title text;

alter table public.event_tasks add column if not exists description text;

alter table public.event_tasks add column if not exists area text;

alter table public.event_tasks add column if not exists priority text;

alter table public.event_tasks add column if not exists status text;

alter table public.event_tasks add column if not exists starts_at timestamptz;

alter table public.event_tasks add column if not exists due_at timestamptz;

alter table public.event_tasks add column if not exists progress integer;

alter table public.event_tasks add column if not exists parent_task_id uuid;

create index if not exists idx_event_tasks_club_id on public.event_tasks(club_id);

-- Eventos: Responsáveis/colaboradores.
create table if not exists public.event_task_assignees (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  task_id uuid,
  profile_id uuid,
  role text
);

alter table public.event_task_assignees add column if not exists club_id uuid;

alter table public.event_task_assignees add column if not exists task_id uuid;

alter table public.event_task_assignees add column if not exists profile_id uuid;

alter table public.event_task_assignees add column if not exists role text;

create index if not exists idx_event_task_assignees_club_id on public.event_task_assignees(club_id);

-- Eventos: Turnos.
create table if not exists public.event_shifts (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid,
  area text,
  starts_at timestamptz,
  ends_at timestamptz,
  required_people integer
);

alter table public.event_shifts add column if not exists club_id uuid;

alter table public.event_shifts add column if not exists event_id uuid;

alter table public.event_shifts add column if not exists area text;

alter table public.event_shifts add column if not exists starts_at timestamptz;

alter table public.event_shifts add column if not exists ends_at timestamptz;

alter table public.event_shifts add column if not exists required_people integer;

create index if not exists idx_event_shifts_club_id on public.event_shifts(club_id);

-- Eventos: Escala de voluntários.
create table if not exists public.event_shift_members (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  shift_id uuid,
  member_id uuid,
  status text,
  actual_hours numeric(14,2)
);

alter table public.event_shift_members add column if not exists club_id uuid;

alter table public.event_shift_members add column if not exists shift_id uuid;

alter table public.event_shift_members add column if not exists member_id uuid;

alter table public.event_shift_members add column if not exists status text;

alter table public.event_shift_members add column if not exists actual_hours numeric(14,2);

create index if not exists idx_event_shift_members_club_id on public.event_shift_members(club_id);

-- Eventos: Programa/cronograma.
create table if not exists public.event_program (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid,
  title text not null,
  starts_at timestamptz,
  ends_at timestamptz,
  location text,
  responsible_profile_id uuid
);

alter table public.event_program add column if not exists club_id uuid;

alter table public.event_program add column if not exists event_id uuid;

alter table public.event_program add column if not exists title text;

alter table public.event_program add column if not exists starts_at timestamptz;

alter table public.event_program add column if not exists ends_at timestamptz;

alter table public.event_program add column if not exists location text;

alter table public.event_program add column if not exists responsible_profile_id uuid;

create index if not exists idx_event_program_club_id on public.event_program(club_id);

-- Eventos: Passeios/Roadbooks.
create table if not exists public.event_routes (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid,
  meeting_point jsonb,
  departure_at timestamptz,
  destination jsonb,
  distance_km numeric(14,2),
  duration_minutes integer,
  gpx_path text,
  road_captain_id uuid,
  sweep_rider_id uuid,
  route_data jsonb
);

alter table public.event_routes add column if not exists club_id uuid;

alter table public.event_routes add column if not exists event_id uuid;

alter table public.event_routes add column if not exists meeting_point jsonb;

alter table public.event_routes add column if not exists departure_at timestamptz;

alter table public.event_routes add column if not exists destination jsonb;

alter table public.event_routes add column if not exists distance_km numeric(14,2);

alter table public.event_routes add column if not exists duration_minutes integer;

alter table public.event_routes add column if not exists gpx_path text;

alter table public.event_routes add column if not exists road_captain_id uuid;

alter table public.event_routes add column if not exists sweep_rider_id uuid;

alter table public.event_routes add column if not exists route_data jsonb;

create index if not exists idx_event_routes_club_id on public.event_routes(club_id);

-- Eventos: Bandas/artistas.
-- Canonical event writer contract from 20260814090737; blueprint extras kept by ADD COLUMN.
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

alter table public.event_bands add column if not exists club_id uuid;

alter table public.event_bands add column if not exists event_id uuid;

alter table public.event_bands add column if not exists name text;

alter table public.event_bands add column if not exists contact jsonb;

alter table public.event_bands add column if not exists fee numeric(14,2);

alter table public.event_bands add column if not exists schedule jsonb;

alter table public.event_bands add column if not exists technical_rider_document_id uuid;

alter table public.event_bands add column if not exists contract_document_id uuid;

alter table public.event_bands add column if not exists payment_status text;

alter table public.event_bands add column if not exists status text;

create index if not exists idx_event_bands_club_id on public.event_bands(club_id);

-- Eventos: Expositores/vendedores.
-- Canonical event writer contract from 20260814090737; blueprint extras kept by ADD COLUMN.
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

alter table public.event_exhibitors add column if not exists club_id uuid;

alter table public.event_exhibitors add column if not exists event_id uuid;

alter table public.event_exhibitors add column if not exists supplier_id uuid;

alter table public.event_exhibitors add column if not exists name text;

alter table public.event_exhibitors add column if not exists category text;

alter table public.event_exhibitors add column if not exists requirements jsonb;

alter table public.event_exhibitors add column if not exists fee numeric(14,2);

alter table public.event_exhibitors add column if not exists deposit numeric(14,2);

alter table public.event_exhibitors add column if not exists location_code text;

alter table public.event_exhibitors add column if not exists payment_status text;

alter table public.event_exhibitors add column if not exists status text;

create index if not exists idx_event_exhibitors_club_id on public.event_exhibitors(club_id);

-- Eventos: Patrocinadores/apoios.
-- Canonical event writer contract from 20260814090737; blueprint extras kept by ADD COLUMN.
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

alter table public.event_sponsors add column if not exists club_id uuid;

alter table public.event_sponsors add column if not exists event_id uuid;

alter table public.event_sponsors add column if not exists name text;

alter table public.event_sponsors add column if not exists support_type text;

alter table public.event_sponsors add column if not exists monetary_value numeric(14,2);

alter table public.event_sponsors add column if not exists in_kind_description text;

alter table public.event_sponsors add column if not exists benefits text;

alter table public.event_sponsors add column if not exists logo_path text;

alter table public.event_sponsors add column if not exists status text;

create index if not exists idx_event_sponsors_club_id on public.event_sponsors(club_id);

-- Eventos: Documentos obrigatórios.
create table if not exists public.event_documents (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid,
  document_type text,
  document_id uuid,
  requested_at date,
  issued_at date,
  expires_at date,
  status text,
  responsible_profile_id uuid
);

alter table public.event_documents add column if not exists club_id uuid;

alter table public.event_documents add column if not exists event_id uuid;

alter table public.event_documents add column if not exists document_type text;

alter table public.event_documents add column if not exists document_id uuid;

alter table public.event_documents add column if not exists requested_at date;

alter table public.event_documents add column if not exists issued_at date;

alter table public.event_documents add column if not exists expires_at date;

alter table public.event_documents add column if not exists status text;

alter table public.event_documents add column if not exists responsible_profile_id uuid;

create index if not exists idx_event_documents_club_id on public.event_documents(club_id);

-- Eventos: Ocorrências.
create table if not exists public.event_incidents (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid,
  incident_type text,
  occurred_at timestamptz,
  location text,
  description text,
  people jsonb,
  actions_taken text,
  status text,
  sensitive boolean
);

alter table public.event_incidents add column if not exists club_id uuid;

alter table public.event_incidents add column if not exists event_id uuid;

alter table public.event_incidents add column if not exists incident_type text;

alter table public.event_incidents add column if not exists occurred_at timestamptz;

alter table public.event_incidents add column if not exists location text;

alter table public.event_incidents add column if not exists description text;

alter table public.event_incidents add column if not exists people jsonb;

alter table public.event_incidents add column if not exists actions_taken text;

alter table public.event_incidents add column if not exists status text;

alter table public.event_incidents add column if not exists sensitive boolean;

create index if not exists idx_event_incidents_club_id on public.event_incidents(club_id);

-- Eventos: Configuração de Octanas.
create table if not exists public.event_octane_configs (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid,
  unit_name text,
  unit_value numeric(14,2),
  packs jsonb,
  active boolean default true
);

alter table public.event_octane_configs add column if not exists club_id uuid;

alter table public.event_octane_configs add column if not exists event_id uuid;

alter table public.event_octane_configs add column if not exists unit_name text;

alter table public.event_octane_configs add column if not exists unit_value numeric(14,2);

alter table public.event_octane_configs add column if not exists packs jsonb;

alter table public.event_octane_configs add column if not exists active boolean default true;

create index if not exists idx_event_octane_configs_club_id on public.event_octane_configs(club_id);

-- Inventário e vendas: Produto genérico.
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  name text not null,
  category text,
  subcategory text,
  description text,
  unit_type text,
  sellable boolean,
  internal_only boolean,
  has_expiry boolean,
  active boolean default true,
  photo_path text
);

alter table public.products add column if not exists club_id uuid;

alter table public.products add column if not exists name text;

alter table public.products add column if not exists category text;

alter table public.products add column if not exists subcategory text;

alter table public.products add column if not exists description text;

alter table public.products add column if not exists unit_type text;

alter table public.products add column if not exists sellable boolean;

alter table public.products add column if not exists internal_only boolean;

alter table public.products add column if not exists has_expiry boolean;

alter table public.products add column if not exists active boolean default true;

alter table public.products add column if not exists photo_path text;

create index if not exists idx_products_club_id on public.products(club_id);

-- Inventário e vendas: SKU por tamanho/cor/formato.
create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  product_id uuid,
  sku text,
  barcode text,
  attributes jsonb,
  cost numeric(12,2),
  sale_price numeric(12,2),
  minimum_stock numeric(12,2) default 0,
  maximum_stock numeric(14,2) default 0,
  active boolean default true
);

alter table public.product_variants add column if not exists club_id uuid;

alter table public.product_variants add column if not exists product_id uuid;

alter table public.product_variants add column if not exists sku text;

alter table public.product_variants add column if not exists barcode text;

alter table public.product_variants add column if not exists attributes jsonb;

alter table public.product_variants add column if not exists cost numeric(14,2);

alter table public.product_variants add column if not exists sale_price numeric(14,2);

alter table public.product_variants add column if not exists minimum_stock numeric(14,2) default 0;

alter table public.product_variants add column if not exists maximum_stock numeric(14,2) default 0;

alter table public.product_variants add column if not exists active boolean default true;

create index if not exists idx_product_variants_club_id on public.product_variants(club_id);

-- Inventário e vendas: Club House, armazém, evento, bar.
create table if not exists public.stock_locations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  name text not null,
  location_type text,
  event_id uuid,
  parent_id uuid,
  active boolean default true
);

alter table public.stock_locations add column if not exists club_id uuid;

alter table public.stock_locations add column if not exists name text;

alter table public.stock_locations add column if not exists location_type text;

alter table public.stock_locations add column if not exists event_id uuid;

alter table public.stock_locations add column if not exists parent_id uuid;

alter table public.stock_locations add column if not exists active boolean default true;

create index if not exists idx_stock_locations_club_id on public.stock_locations(club_id);

-- Inventário e vendas: Lotes e validade.
create table if not exists public.stock_lots (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  product_variant_id uuid,
  location_id uuid,
  lot_number text,
  received_at date,
  expires_at date,
  quantity numeric(14,2),
  unit_cost numeric(14,2),
  supplier_id uuid
);

alter table public.stock_lots add column if not exists club_id uuid;

alter table public.stock_lots add column if not exists product_variant_id uuid;

alter table public.stock_lots add column if not exists location_id uuid;

alter table public.stock_lots add column if not exists lot_number text;

alter table public.stock_lots add column if not exists received_at date;

alter table public.stock_lots add column if not exists expires_at date;

alter table public.stock_lots add column if not exists quantity numeric(14,2);

alter table public.stock_lots add column if not exists unit_cost numeric(14,2);

alter table public.stock_lots add column if not exists supplier_id uuid;

create index if not exists idx_stock_lots_club_id on public.stock_lots(club_id);

-- Inventário e vendas: Ledger de stock.
create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  product_variant_id uuid,
  movement_type text,
  quantity numeric(12,2),
  from_location_id uuid,
  to_location_id uuid,
  lot_id uuid,
  event_id uuid,
  member_id uuid,
  source_table text,
  source_id uuid,
  unit_cost numeric(12,2),
  occurred_at timestamptz,
  confirmed_by uuid
);

alter table public.stock_movements add column if not exists club_id uuid;

alter table public.stock_movements add column if not exists product_variant_id uuid;

alter table public.stock_movements add column if not exists movement_type text;

alter table public.stock_movements add column if not exists quantity numeric(14,2);

alter table public.stock_movements add column if not exists from_location_id uuid;

alter table public.stock_movements add column if not exists to_location_id uuid;

alter table public.stock_movements add column if not exists lot_id uuid;

alter table public.stock_movements add column if not exists event_id uuid;

alter table public.stock_movements add column if not exists member_id uuid;

alter table public.stock_movements add column if not exists source_table text;

alter table public.stock_movements add column if not exists source_id uuid;

alter table public.stock_movements add column if not exists unit_cost numeric(14,2);

alter table public.stock_movements add column if not exists occurred_at timestamptz;

alter table public.stock_movements add column if not exists confirmed_by uuid;

create index if not exists idx_stock_movements_club_id on public.stock_movements(club_id);

-- Inventário e vendas: Reserva 30 dias.
create table if not exists public.stock_reservations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  product_variant_id uuid,
  member_id uuid,
  external_customer_id uuid,
  quantity numeric(14,2),
  reserved_at timestamptz,
  expires_at timestamptz,
  status text,
  sales_order_id uuid
);

alter table public.stock_reservations add column if not exists club_id uuid;

alter table public.stock_reservations add column if not exists product_variant_id uuid;

alter table public.stock_reservations add column if not exists member_id uuid;

alter table public.stock_reservations add column if not exists external_customer_id uuid;

alter table public.stock_reservations add column if not exists quantity numeric(14,2);

alter table public.stock_reservations add column if not exists reserved_at timestamptz;

alter table public.stock_reservations add column if not exists expires_at timestamptz;

alter table public.stock_reservations add column if not exists status text;

alter table public.stock_reservations add column if not exists sales_order_id uuid;

create index if not exists idx_stock_reservations_club_id on public.stock_reservations(club_id);

-- Inventário e vendas: Sessão de contagem.
create table if not exists public.physical_inventories (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  location_id uuid,
  status text,
  started_at timestamptz,
  closed_at timestamptz,
  approved_by uuid
);

alter table public.physical_inventories add column if not exists club_id uuid;

alter table public.physical_inventories add column if not exists location_id uuid;

alter table public.physical_inventories add column if not exists status text;

alter table public.physical_inventories add column if not exists started_at timestamptz;

alter table public.physical_inventories add column if not exists closed_at timestamptz;

alter table public.physical_inventories add column if not exists approved_by uuid;

create index if not exists idx_physical_inventories_club_id on public.physical_inventories(club_id);

-- Inventário e vendas: Contagem por variante/lote.
create table if not exists public.inventory_counts (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  inventory_id uuid,
  variant_id uuid,
  lot_id uuid,
  expected_quantity numeric(14,2),
  counted_quantity numeric(14,2),
  difference numeric(14,2),
  reason text
);

alter table public.inventory_counts add column if not exists club_id uuid;

alter table public.inventory_counts add column if not exists inventory_id uuid;

alter table public.inventory_counts add column if not exists variant_id uuid;

alter table public.inventory_counts add column if not exists lot_id uuid;

alter table public.inventory_counts add column if not exists expected_quantity numeric(14,2);

alter table public.inventory_counts add column if not exists counted_quantity numeric(14,2);

alter table public.inventory_counts add column if not exists difference numeric(14,2);

alter table public.inventory_counts add column if not exists reason text;

create index if not exists idx_inventory_counts_club_id on public.inventory_counts(club_id);

-- Inventário e vendas: Clientes externos.
create table if not exists public.external_customers (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  name text not null,
  phone text,
  email text,
  tax_number text,
  address jsonb,
  notes text
);

alter table public.external_customers add column if not exists club_id uuid;

alter table public.external_customers add column if not exists name text;

alter table public.external_customers add column if not exists phone text;

alter table public.external_customers add column if not exists email text;

alter table public.external_customers add column if not exists tax_number text;

alter table public.external_customers add column if not exists address jsonb;

alter table public.external_customers add column if not exists notes text;

create index if not exists idx_external_customers_club_id on public.external_customers(club_id);

-- Inventário e vendas: Venda/encomenda.
create table if not exists public.sales_orders (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  order_number text,
  member_id uuid,
  external_customer_id uuid,
  event_id uuid,
  status text,
  subtotal numeric(14,2),
  discount numeric(14,2),
  total numeric(14,2),
  payment_method_id uuid,
  transaction_id uuid,
  delivery_method text,
  delivery_data jsonb,
  created_at timestamptz not null default now()
);

alter table public.sales_orders add column if not exists club_id uuid;

alter table public.sales_orders add column if not exists order_number text;

alter table public.sales_orders add column if not exists member_id uuid;

alter table public.sales_orders add column if not exists external_customer_id uuid;

alter table public.sales_orders add column if not exists event_id uuid;

alter table public.sales_orders add column if not exists status text;

alter table public.sales_orders add column if not exists subtotal numeric(14,2);

alter table public.sales_orders add column if not exists discount numeric(14,2);

alter table public.sales_orders add column if not exists total numeric(14,2);

alter table public.sales_orders add column if not exists payment_method_id uuid;

alter table public.sales_orders add column if not exists transaction_id uuid;

alter table public.sales_orders add column if not exists delivery_method text;

alter table public.sales_orders add column if not exists delivery_data jsonb;

alter table public.sales_orders add column if not exists created_at timestamptz default now();

create index if not exists idx_sales_orders_club_id on public.sales_orders(club_id);

-- Inventário e vendas: Linhas de venda.
create table if not exists public.sales_order_lines (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  sales_order_id uuid,
  product_variant_id uuid,
  quantity numeric(14,2),
  unit_price numeric(14,2),
  discount numeric(14,2),
  line_total numeric(14,2)
);

alter table public.sales_order_lines add column if not exists club_id uuid;

alter table public.sales_order_lines add column if not exists sales_order_id uuid;

alter table public.sales_order_lines add column if not exists product_variant_id uuid;

alter table public.sales_order_lines add column if not exists quantity numeric(14,2);

alter table public.sales_order_lines add column if not exists unit_price numeric(14,2);

alter table public.sales_order_lines add column if not exists discount numeric(14,2);

alter table public.sales_order_lines add column if not exists line_total numeric(14,2);

create index if not exists idx_sales_order_lines_club_id on public.sales_order_lines(club_id);

-- Inventário e vendas: Workflow de aprovação de patches.
create table if not exists public.patch_delivery_requests (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  variant_id uuid,
  requested_by uuid,
  reason text,
  status text,
  approved_by uuid,
  delivered_at date
);

alter table public.patch_delivery_requests add column if not exists club_id uuid;

alter table public.patch_delivery_requests add column if not exists member_id uuid;

alter table public.patch_delivery_requests add column if not exists variant_id uuid;

alter table public.patch_delivery_requests add column if not exists requested_by uuid;

alter table public.patch_delivery_requests add column if not exists reason text;

alter table public.patch_delivery_requests add column if not exists status text;

alter table public.patch_delivery_requests add column if not exists approved_by uuid;

alter table public.patch_delivery_requests add column if not exists delivered_at date;

create index if not exists idx_patch_delivery_requests_club_id on public.patch_delivery_requests(club_id);

-- Documentos e comunicação: Metadados comuns de ficheiros.
create table if not exists public.attachments (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  storage_bucket text,
  storage_path text,
  file_name text,
  mime_type text,
  size_bytes bigint,
  checksum text,
  owner_profile_id uuid,
  visibility text,
  created_at timestamptz not null default now()
);

alter table public.attachments add column if not exists club_id uuid;

alter table public.attachments add column if not exists storage_bucket text;

alter table public.attachments add column if not exists storage_path text;

alter table public.attachments add column if not exists file_name text;

alter table public.attachments add column if not exists mime_type text;

alter table public.attachments add column if not exists size_bytes bigint;

alter table public.attachments add column if not exists checksum text;

alter table public.attachments add column if not exists owner_profile_id uuid;

alter table public.attachments add column if not exists visibility text;

alter table public.attachments add column if not exists created_at timestamptz default now();

create index if not exists idx_attachments_club_id on public.attachments(club_id);

-- Documentos e comunicação: Registo lógico documental.
create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  code text,
  name text not null,
  category text,
  subcategory text,
  document_date date,
  expires_at date,
  status text,
  current_version_id uuid,
  owner_member_id uuid,
  sensitive boolean,
  description text,
  tags text
);

alter table public.documents add column if not exists club_id uuid;

alter table public.documents add column if not exists code text;

alter table public.documents add column if not exists name text;

alter table public.documents add column if not exists category text;

alter table public.documents add column if not exists subcategory text;

alter table public.documents add column if not exists document_date date;

alter table public.documents add column if not exists expires_at date;

alter table public.documents add column if not exists status text;

alter table public.documents add column if not exists current_version_id uuid;

alter table public.documents add column if not exists owner_member_id uuid;

alter table public.documents add column if not exists sensitive boolean;

alter table public.documents add column if not exists description text;

alter table public.documents add column if not exists tags text[];

create index if not exists idx_documents_club_id on public.documents(club_id);

-- Documentos e comunicação: Versões imutáveis.
create table if not exists public.document_versions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  document_id uuid not null constraint fk_document_versions_document_id references public.documents(id) on delete cascade,
  version_no integer not null check (version_no > 0),
  version_label text not null,
  storage_path text not null,
  original_file_name text,
  mime_type text,
  file_size bigint not null default 0 check (file_size >= 0),
  change_notes text,
  is_current boolean not null default true,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique(document_id, version_no),
  unique(storage_path)
);

alter table public.document_versions add column if not exists club_id uuid;

alter table public.document_versions add column if not exists document_id uuid;

alter table public.document_versions add column if not exists version_number integer;

alter table public.document_versions add column if not exists attachment_id uuid;

alter table public.document_versions add column if not exists change_notes text;

alter table public.document_versions add column if not exists created_by uuid;

alter table public.document_versions add column if not exists created_at timestamptz default now();

create index if not exists idx_document_versions_club_id on public.document_versions(club_id);

-- Documentos e comunicação: Associação polimórfica.
create table if not exists public.document_links (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  document_id uuid not null references public.documents(id) on delete cascade,
  link_type text not null default 'related',
  linked_entity_type text not null,
  linked_entity_id uuid,
  label text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique(document_id,link_type,linked_entity_type,linked_entity_id)
);

alter table public.document_links add column if not exists club_id uuid;

alter table public.document_links add column if not exists document_id uuid;

alter table public.document_links add column if not exists entity_type text;

alter table public.document_links add column if not exists entity_id uuid;

alter table public.document_links add column if not exists link_role text;

create index if not exists idx_document_links_club_id on public.document_links(club_id);

-- Documentos e comunicação: Aprovação/revisão.
create table if not exists public.document_approvals (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  document_id uuid,
  status text,
  requested_by uuid,
  reviewed_by uuid,
  comments text,
  reviewed_at timestamptz
);

alter table public.document_approvals add column if not exists club_id uuid;

alter table public.document_approvals add column if not exists document_id uuid;

alter table public.document_approvals add column if not exists status text;

alter table public.document_approvals add column if not exists requested_by uuid;

alter table public.document_approvals add column if not exists reviewed_by uuid;

alter table public.document_approvals add column if not exists comments text;

alter table public.document_approvals add column if not exists reviewed_at timestamptz;

create index if not exists idx_document_approvals_club_id on public.document_approvals(club_id);

-- Documentos e comunicação: Downloads/aberturas sensíveis.
create table if not exists public.document_access_log (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  document_id uuid,
  profile_id uuid,
  action text,
  reason text,
  created_at timestamptz not null default now()
);

alter table public.document_access_log add column if not exists club_id uuid;

alter table public.document_access_log add column if not exists document_id uuid;

alter table public.document_access_log add column if not exists profile_id uuid;

alter table public.document_access_log add column if not exists action text;

alter table public.document_access_log add column if not exists reason text;

alter table public.document_access_log add column if not exists created_at timestamptz default now();

create index if not exists idx_document_access_log_club_id on public.document_access_log(club_id);

-- Documentos e comunicação: Texto e campos extraídos.
create table if not exists public.document_ocr (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  document_version_id uuid,
  status text,
  extracted_text text,
  extracted_fields jsonb,
  confidence numeric(14,2),
  processed_at timestamptz
);

alter table public.document_ocr add column if not exists club_id uuid;

alter table public.document_ocr add column if not exists document_version_id uuid;

alter table public.document_ocr add column if not exists status text;

alter table public.document_ocr add column if not exists extracted_text text;

alter table public.document_ocr add column if not exists extracted_fields jsonb;

alter table public.document_ocr add column if not exists confidence numeric(14,2);

alter table public.document_ocr add column if not exists processed_at timestamptz;

create index if not exists idx_document_ocr_club_id on public.document_ocr(club_id);

-- Documentos e comunicação: Cápsula do Tempo.
create table if not exists public.annual_books (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  year integer,
  title text not null,
  status text,
  cover_attachment_id uuid,
  final_pdf_attachment_id uuid,
  approved_by uuid
);

alter table public.annual_books add column if not exists club_id uuid;

alter table public.annual_books add column if not exists year integer;

alter table public.annual_books add column if not exists title text;

alter table public.annual_books add column if not exists status text;

alter table public.annual_books add column if not exists cover_attachment_id uuid;

alter table public.annual_books add column if not exists final_pdf_attachment_id uuid;

alter table public.annual_books add column if not exists approved_by uuid;

create index if not exists idx_annual_books_club_id on public.annual_books(club_id);

-- Documentos e comunicação: Capítulos/itens.
create table if not exists public.annual_book_items (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  annual_book_id uuid,
  item_type text,
  source_table text,
  source_id uuid,
  title text not null,
  body text,
  sort_order integer,
  included boolean
);

alter table public.annual_book_items add column if not exists club_id uuid;

alter table public.annual_book_items add column if not exists annual_book_id uuid;

alter table public.annual_book_items add column if not exists item_type text;

alter table public.annual_book_items add column if not exists source_table text;

alter table public.annual_book_items add column if not exists source_id uuid;

alter table public.annual_book_items add column if not exists title text;

alter table public.annual_book_items add column if not exists body text;

alter table public.annual_book_items add column if not exists sort_order integer;

alter table public.annual_book_items add column if not exists included boolean;

create index if not exists idx_annual_book_items_club_id on public.annual_book_items(club_id);

-- Documentos e comunicação: Comunicados.
create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  title text not null,
  body text,
  priority text,
  visibility text,
  comments_enabled boolean,
  published_at timestamptz,
  expires_at timestamptz,
  created_by uuid
);

alter table public.announcements add column if not exists club_id uuid;

alter table public.announcements add column if not exists title text;

alter table public.announcements add column if not exists body text;

alter table public.announcements add column if not exists priority text;

alter table public.announcements add column if not exists visibility text;

alter table public.announcements add column if not exists comments_enabled boolean;

alter table public.announcements add column if not exists published_at timestamptz;

alter table public.announcements add column if not exists expires_at timestamptz;

alter table public.announcements add column if not exists created_by uuid;

create index if not exists idx_announcements_club_id on public.announcements(club_id);

-- Documentos e comunicação: Destinatários/leitura.
create table if not exists public.announcement_recipients (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  announcement_id uuid,
  profile_id uuid,
  read_at timestamptz,
  confirmed_at timestamptz
);

alter table public.announcement_recipients add column if not exists club_id uuid;

alter table public.announcement_recipients add column if not exists announcement_id uuid;

alter table public.announcement_recipients add column if not exists profile_id uuid;

alter table public.announcement_recipients add column if not exists read_at timestamptz;

alter table public.announcement_recipients add column if not exists confirmed_at timestamptz;

create index if not exists idx_announcement_recipients_club_id on public.announcement_recipients(club_id);

-- Documentos e comunicação: Votações.
-- polls is created with its real contract by 20260830182741.

-- Documentos e comunicação: Opções.
-- poll_options is created with its real contract by 20260830182741.

-- Documentos e comunicação: Votos.
-- poll_votes is created with its real contract by 20260830182741.

-- Plataforma e futuro: Centro de notificações.
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  profile_id uuid,
  type text,
  priority text,
  title text not null,
  body text,
  action_route text,
  source_table text,
  source_id uuid,
  read_at timestamptz,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.notifications add column if not exists club_id uuid;

alter table public.notifications add column if not exists profile_id uuid;

alter table public.notifications add column if not exists type text;

alter table public.notifications add column if not exists priority text;

alter table public.notifications add column if not exists title text;

alter table public.notifications add column if not exists body text;

alter table public.notifications add column if not exists action_route text;

alter table public.notifications add column if not exists source_table text;

alter table public.notifications add column if not exists source_id uuid;

alter table public.notifications add column if not exists read_at timestamptz;

alter table public.notifications add column if not exists resolved_at timestamptz;

alter table public.notifications add column if not exists created_at timestamptz default now();

create index if not exists idx_notifications_club_id on public.notifications(club_id);

-- Plataforma e futuro: Feed com visibilidade.
create table if not exists public.activity_feed (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  actor_profile_id uuid,
  activity_type text,
  title text not null,
  description text,
  visibility text,
  source_table text,
  source_id uuid,
  created_at timestamptz not null default now()
);

alter table public.activity_feed add column if not exists club_id uuid;

alter table public.activity_feed add column if not exists actor_profile_id uuid;

alter table public.activity_feed add column if not exists activity_type text;

alter table public.activity_feed add column if not exists title text;

alter table public.activity_feed add column if not exists description text;

alter table public.activity_feed add column if not exists visibility text;

alter table public.activity_feed add column if not exists source_table text;

alter table public.activity_feed add column if not exists source_id uuid;

alter table public.activity_feed add column if not exists created_at timestamptz default now();

create index if not exists idx_activity_feed_club_id on public.activity_feed(club_id);

-- Plataforma e futuro: Auditoria append-only.
create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  club_id uuid not null,
  actor_profile_id uuid,
  action text,
  entity_type text,
  entity_id text,
  data jsonb,
  old_data jsonb,
  new_data jsonb,
  reason text,
  ip_address inet,
  user_agent text,
  created_at timestamptz not null default now()
);

alter table public.audit_log add column if not exists club_id uuid;

alter table public.audit_log add column if not exists actor_profile_id uuid;

alter table public.audit_log add column if not exists action text;

alter table public.audit_log add column if not exists entity_type text;

alter table public.audit_log add column if not exists entity_id text;

alter table public.audit_log add column if not exists old_data jsonb;

alter table public.audit_log add column if not exists new_data jsonb;

alter table public.audit_log add column if not exists reason text;

alter table public.audit_log add column if not exists ip_address inet;

alter table public.audit_log add column if not exists user_agent text;

alter table public.audit_log add column if not exists created_at timestamptz default now();

create index if not exists idx_audit_log_club_id on public.audit_log(club_id);

-- Plataforma e futuro: Execução de importação.
-- imports is created with its real contract by 20260813070834.

-- Plataforma e futuro: Pré-visualização/editável.
-- import_rows is created with its real contract by 20260813070834.

-- Plataforma e futuro: Exportações e pacotes integrais.
-- exports is created by 20260812210544; omit the conflicting blueprint table.

-- Plataforma e futuro: Relatórios agendados.
create table if not exists public.scheduled_reports (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  report_code text,
  schedule text,
  filters jsonb,
  recipients jsonb,
  active boolean default true
);

alter table public.scheduled_reports add column if not exists club_id uuid;

alter table public.scheduled_reports add column if not exists report_code text;

alter table public.scheduled_reports add column if not exists schedule text;

alter table public.scheduled_reports add column if not exists filters jsonb;

alter table public.scheduled_reports add column if not exists recipients jsonb;

alter table public.scheduled_reports add column if not exists active boolean default true;

create index if not exists idx_scheduled_reports_club_id on public.scheduled_reports(club_id);

-- Plataforma e futuro: Métodos configuráveis.
create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  code text,
  name text not null,
  active boolean default true
);

alter table public.payment_methods add column if not exists club_id uuid;

alter table public.payment_methods add column if not exists code text;

alter table public.payment_methods add column if not exists name text;

alter table public.payment_methods add column if not exists active boolean default true;

create index if not exists idx_payment_methods_club_id on public.payment_methods(club_id);

-- Plataforma e futuro: Numerações automáticas.
create table if not exists public.number_sequences (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  sequence_code text,
  prefix_template text,
  next_value bigint,
  padding integer
);

alter table public.number_sequences add column if not exists club_id uuid;

alter table public.number_sequences add column if not exists sequence_code text;

alter table public.number_sequences add column if not exists prefix_template text;

alter table public.number_sequences add column if not exists next_value bigint;

alter table public.number_sequences add column if not exists padding integer;

create index if not exists idx_number_sequences_club_id on public.number_sequences(club_id);

-- Plataforma e futuro: Futuro: modelo impresso.
create table if not exists public.consumption_card_templates (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  name text not null,
  version integer,
  layout_definition jsonb,
  active boolean default true
);

alter table public.consumption_card_templates add column if not exists club_id uuid;

alter table public.consumption_card_templates add column if not exists name text;

alter table public.consumption_card_templates add column if not exists version integer;

alter table public.consumption_card_templates add column if not exists layout_definition jsonb;

alter table public.consumption_card_templates add column if not exists active boolean default true;

create index if not exists idx_consumption_card_templates_club_id on public.consumption_card_templates(club_id);

-- Plataforma e futuro: Futuro: sessão de cartão.
create table if not exists public.consumption_cards (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  card_number text,
  template_id uuid,
  holder_type text,
  member_id uuid,
  visitor_id uuid,
  host_member_id uuid,
  event_id uuid,
  status text,
  opened_at timestamptz,
  closed_at timestamptz
);

alter table public.consumption_cards add column if not exists club_id uuid;

alter table public.consumption_cards add column if not exists card_number text;

alter table public.consumption_cards add column if not exists template_id uuid;

alter table public.consumption_cards add column if not exists holder_type text;

alter table public.consumption_cards add column if not exists member_id uuid;

alter table public.consumption_cards add column if not exists visitor_id uuid;

alter table public.consumption_cards add column if not exists host_member_id uuid;

alter table public.consumption_cards add column if not exists event_id uuid;

alter table public.consumption_cards add column if not exists status text;

alter table public.consumption_cards add column if not exists opened_at timestamptz;

alter table public.consumption_cards add column if not exists closed_at timestamptz;

create index if not exists idx_consumption_cards_club_id on public.consumption_cards(club_id);

-- Plataforma e futuro: Futuro: fotografia/OCR.
create table if not exists public.consumption_card_scans (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  card_id uuid,
  attachment_id uuid,
  detected_data jsonb,
  confidence numeric(14,2),
  status text,
  confirmed_by uuid
);

alter table public.consumption_card_scans add column if not exists club_id uuid;

alter table public.consumption_card_scans add column if not exists card_id uuid;

alter table public.consumption_card_scans add column if not exists attachment_id uuid;

alter table public.consumption_card_scans add column if not exists detected_data jsonb;

alter table public.consumption_card_scans add column if not exists confidence numeric(14,2);

alter table public.consumption_card_scans add column if not exists status text;

alter table public.consumption_card_scans add column if not exists confirmed_by uuid;

create index if not exists idx_consumption_card_scans_club_id on public.consumption_card_scans(club_id);

-- Plataforma e futuro: Futuro: consumos.
create table if not exists public.consumption_card_lines (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  card_id uuid,
  product_variant_id uuid,
  quantity numeric(14,2),
  unit_price_snapshot numeric(14,2),
  line_total numeric(14,2),
  source text
);

alter table public.consumption_card_lines add column if not exists club_id uuid;

alter table public.consumption_card_lines add column if not exists card_id uuid;

alter table public.consumption_card_lines add column if not exists product_variant_id uuid;

alter table public.consumption_card_lines add column if not exists quantity numeric(14,2);

alter table public.consumption_card_lines add column if not exists unit_price_snapshot numeric(14,2);

alter table public.consumption_card_lines add column if not exists line_total numeric(14,2);

alter table public.consumption_card_lines add column if not exists source text;

create index if not exists idx_consumption_card_lines_club_id on public.consumption_card_lines(club_id);

-- Plataforma e futuro: Futuro: visitante simplificado.
create table if not exists public.clubhouse_visitors (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  name text not null,
  phone text,
  email text,
  notes text
);

alter table public.clubhouse_visitors add column if not exists club_id uuid;

alter table public.clubhouse_visitors add column if not exists name text;

alter table public.clubhouse_visitors add column if not exists phone text;

alter table public.clubhouse_visitors add column if not exists email text;

alter table public.clubhouse_visitors add column if not exists notes text;

create index if not exists idx_clubhouse_visitors_club_id on public.clubhouse_visitors(club_id);

do $$ begin
 alter table public.club_memberships add constraint fk_club_memberships_club_id
 foreign key (club_id) references public.clubs(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;

do $$ begin
 alter table public.club_memberships add constraint fk_club_memberships_profile_id
 foreign key (profile_id) references public.profiles(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;

do $$ begin
 alter table public.members add constraint fk_members_club_id
 foreign key (club_id) references public.clubs(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;

do $$ begin
 alter table public.member_emergency_data add constraint fk_member_emergency_data_member_id
 foreign key (member_id) references public.members(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;

do $$ begin
 alter table public.member_positions add constraint fk_member_positions_member_id
 foreign key (member_id) references public.members(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;

do $$ begin
 alter table public.member_positions add constraint fk_member_positions_position_id
 foreign key (position_id) references public.club_positions(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;

do $$ begin
 alter table public.motorcycles add constraint fk_motorcycles_member_id
 foreign key (member_id) references public.members(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;

do $$ begin
 alter table public.maintenance_records add constraint fk_maintenance_records_motorcycle_id
 foreign key (motorcycle_id) references public.motorcycles(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;

do $$ begin
 alter table public.fee_obligations add constraint fk_fee_obligations_member_id
 foreign key (member_id) references public.members(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;

do $$ begin
 alter table public.fee_payments add constraint fk_fee_payments_obligation_id
 foreign key (obligation_id) references public.fee_obligations(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;

do $$ begin
 alter table public.event_participants add constraint fk_event_participants_event_id
 foreign key (event_id) references public.events(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;

do $$ begin
 alter table public.event_participants add constraint fk_event_participants_member_id
 foreign key (member_id) references public.members(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;

do $$ begin
 alter table public.product_variants add constraint fk_product_variants_product_id
 foreign key (product_id) references public.products(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;

-- Reconstruction only: captured production has no legacy product_variant_id FK.
-- Preserve stock ledger when a legacy-linked variant is deleted.

do $$ begin
 alter table public.document_versions add constraint fk_document_versions_document_id
 foreign key (document_id) references public.documents(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;

do $$ begin
 alter table public.notifications add constraint fk_notifications_profile_id
 foreign key (profile_id) references public.profiles(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;


create or replace function public.current_profile_id()
returns uuid language sql stable as $$ select auth.uid(); $$;

create or replace function public.has_club_access(target_club uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.club_memberships cm
 where cm.club_id=target_club and cm.profile_id=auth.uid() and coalesce(cm.active,true));
$$;

-- Obsolete has_permission omitted: absent in production, no versioned callers.
-- Its membership_id/effect references never matched the tables declared above.

create or replace function public.audit_event(
 target_club uuid, p_action text, p_entity_type text, p_entity_id text,
 p_old jsonb default null, p_new jsonb default null, p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
 insert into public.audit_log(club_id,actor_profile_id,action,entity_type,entity_id,old_data,new_data,reason,created_at)
 values(target_club,auth.uid(),p_action,p_entity_type,p_entity_id,p_old,p_new,p_reason,now());
end; $$;


alter table public.clubs enable row level security;

drop policy if exists clubs_tenant on public.clubs; create policy clubs_tenant on public.clubs for select to authenticated using(public.has_club_access(id));

alter table public.profiles enable row level security;

drop policy if exists profiles_self on public.profiles; create policy profiles_self on public.profiles for select to authenticated using(id=auth.uid());

alter table public.club_memberships enable row level security;

-- Membership SELECT policies installed after the canonical has_club_role bootstrap below.

alter table public.roles enable row level security;

do $$ begin
   execute 'drop policy if exists roles_tenant on public.roles';
   execute 'create policy roles_tenant on public.roles for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.permissions enable row level security;

do $$ begin
   execute 'drop policy if exists permissions_tenant on public.permissions';
   execute 'create policy permissions_tenant on public.permissions for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.role_permissions enable row level security;

do $$ begin
   execute 'drop policy if exists role_permissions_tenant on public.role_permissions';
   execute 'create policy role_permissions_tenant on public.role_permissions for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.membership_roles enable row level security;

do $$ begin
   execute 'drop policy if exists membership_roles_tenant on public.membership_roles';
   execute 'create policy membership_roles_tenant on public.membership_roles for all to authenticated using(exists(select 1 from public.club_memberships cm where cm.id=club_membership_id and public.has_club_access(cm.club_id))) with check(exists(select 1 from public.club_memberships cm where cm.id=club_membership_id and public.has_club_access(cm.club_id)))';
  exception when undefined_column then null; end $$;

alter table public.user_permission_overrides enable row level security;

-- The dynamic-permissions migration installs self-read and super_admin manage.
-- A permissive tenant FOR ALL policy would let a member grant own permissions.

alter table public.permission_change_log enable row level security;

do $$ begin
   execute 'drop policy if exists permission_change_log_tenant on public.permission_change_log';
   execute 'create policy permission_change_log_tenant on public.permission_change_log for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.members enable row level security;

-- Policy hardening: members_tenant restricted to SELECT.
-- Preserve baseline club read access; final members_manage guards all writes.
create policy members_tenant on public.members for select to authenticated using(public.has_club_access(club_id));

alter table public.member_emergency_data enable row level security;

do $$ begin
   execute 'drop policy if exists member_emergency_data_tenant on public.member_emergency_data';
   execute 'create policy member_emergency_data_tenant on public.member_emergency_data for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.member_status_history enable row level security;

-- Policy hardening: member_status_history_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.club_positions enable row level security;

-- Policy hardening: club_positions_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.member_positions enable row level security;

-- Policy hardening: member_positions_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.member_patch_awards enable row level security;

-- Policy hardening: member_patch_awards_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.assigned_assets enable row level security;

do $$ begin
   execute 'drop policy if exists assigned_assets_tenant on public.assigned_assets';
   execute 'create policy assigned_assets_tenant on public.assigned_assets for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.member_timeline enable row level security;

-- Policy hardening: member_timeline_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.motorcycles enable row level security;

do $$ begin
   execute 'drop policy if exists motorcycles_tenant on public.motorcycles';
   execute 'create policy motorcycles_tenant on public.motorcycles for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.motorcycle_photos enable row level security;

do $$ begin
   execute 'drop policy if exists motorcycle_photos_tenant on public.motorcycle_photos';
   execute 'create policy motorcycle_photos_tenant on public.motorcycle_photos for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.motorcycle_ownership_history enable row level security;

do $$ begin
   execute 'drop policy if exists motorcycle_ownership_history_tenant on public.motorcycle_ownership_history';
   execute 'create policy motorcycle_ownership_history_tenant on public.motorcycle_ownership_history for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.maintenance_records enable row level security;

-- Policy hardening: maintenance_records_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.maintenance_attachments enable row level security;

-- Policy hardening: maintenance_attachments_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.motorcycle_documents enable row level security;

do $$ begin
   execute 'drop policy if exists motorcycle_documents_tenant on public.motorcycle_documents';
   execute 'create policy motorcycle_documents_tenant on public.motorcycle_documents for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.financial_accounts enable row level security;

do $$ begin
   execute 'drop policy if exists financial_accounts_tenant on public.financial_accounts';
   execute 'create policy financial_accounts_tenant on public.financial_accounts for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.funds enable row level security;

do $$ begin
   execute 'drop policy if exists funds_tenant on public.funds';
   execute 'create policy funds_tenant on public.funds for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.cost_centers enable row level security;

-- Policy hardening: cost_centers_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.financial_categories enable row level security;

do $$ begin
   execute 'drop policy if exists financial_categories_tenant on public.financial_categories';
   execute 'create policy financial_categories_tenant on public.financial_categories for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.financial_transactions enable row level security;

do $$ begin
   execute 'drop policy if exists financial_transactions_tenant on public.financial_transactions';
   execute 'create policy financial_transactions_tenant on public.financial_transactions for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.transaction_allocations enable row level security;

do $$ begin
   execute 'drop policy if exists transaction_allocations_tenant on public.transaction_allocations';
   execute 'create policy transaction_allocations_tenant on public.transaction_allocations for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.suppliers enable row level security;

do $$ begin
   execute 'drop policy if exists suppliers_tenant on public.suppliers';
   execute 'create policy suppliers_tenant on public.suppliers for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

-- payables RLS is defined by its actual historical migration.

-- receivables RLS is defined by its actual historical migration.

alter table public.reimbursement_requests enable row level security;

do $$ begin
   execute 'drop policy if exists reimbursement_requests_tenant on public.reimbursement_requests';
   execute 'create policy reimbursement_requests_tenant on public.reimbursement_requests for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

-- cash_sessions RLS is defined by its actual historical migration.

-- bank_reconciliations RLS is defined by its actual historical migration.

-- budgets RLS is defined by its actual historical migration.

-- budget_lines RLS is defined by its actual historical migration.

alter table public.fee_plans enable row level security;

-- Policy hardening: fee_plans_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.member_fee_assignments enable row level security;

do $$ begin
   execute 'drop policy if exists member_fee_assignments_tenant on public.member_fee_assignments';
   execute 'create policy member_fee_assignments_tenant on public.member_fee_assignments for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.fee_obligations enable row level security;

-- Policy hardening: fee_obligations_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.fee_payments enable row level security;

-- Policy hardening: fee_payments_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.fee_payment_allocations enable row level security;

-- Policy hardening: fee_payment_allocations_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.fee_credits enable row level security;

-- Policy hardening: fee_credits_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.fee_exemptions enable row level security;

-- Policy hardening: fee_exemptions_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.fee_adjustments enable row level security;

-- Policy hardening: fee_adjustments_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.fee_receipts enable row level security;

do $$ begin
   execute 'drop policy if exists fee_receipts_tenant on public.fee_receipts';
   execute 'create policy fee_receipts_tenant on public.fee_receipts for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.reported_payments enable row level security;

-- Policy hardening: reported_payments_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.prospect_enrollment_fees enable row level security;

do $$ begin
   execute 'drop policy if exists prospect_enrollment_fees_tenant on public.prospect_enrollment_fees';
   execute 'create policy prospect_enrollment_fees_tenant on public.prospect_enrollment_fees for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.lottery_groups enable row level security;

do $$ begin
   execute 'drop policy if exists lottery_groups_tenant on public.lottery_groups';
   execute 'create policy lottery_groups_tenant on public.lottery_groups for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.lottery_participants enable row level security;

do $$ begin
   execute 'drop policy if exists lottery_participants_tenant on public.lottery_participants';
   execute 'create policy lottery_participants_tenant on public.lottery_participants for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.participant_keys enable row level security;

do $$ begin
   execute 'drop policy if exists participant_keys_tenant on public.participant_keys';
   execute 'create policy participant_keys_tenant on public.participant_keys for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.lottery_periods enable row level security;

do $$ begin
   execute 'drop policy if exists lottery_periods_tenant on public.lottery_periods';
   execute 'create policy lottery_periods_tenant on public.lottery_periods for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.lottery_contributions enable row level security;

do $$ begin
   execute 'drop policy if exists lottery_contributions_tenant on public.lottery_contributions';
   execute 'create policy lottery_contributions_tenant on public.lottery_contributions for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.lottery_draws enable row level security;

do $$ begin
   execute 'drop policy if exists lottery_draws_tenant on public.lottery_draws';
   execute 'create policy lottery_draws_tenant on public.lottery_draws for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.lottery_bets enable row level security;

do $$ begin
   execute 'drop policy if exists lottery_bets_tenant on public.lottery_bets';
   execute 'create policy lottery_bets_tenant on public.lottery_bets for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.lottery_bet_keys enable row level security;

do $$ begin
   execute 'drop policy if exists lottery_bet_keys_tenant on public.lottery_bet_keys';
   execute 'create policy lottery_bet_keys_tenant on public.lottery_bet_keys for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.lottery_results enable row level security;

do $$ begin
   execute 'drop policy if exists lottery_results_tenant on public.lottery_results';
   execute 'create policy lottery_results_tenant on public.lottery_results for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.lottery_matches enable row level security;

do $$ begin
   execute 'drop policy if exists lottery_matches_tenant on public.lottery_matches';
   execute 'create policy lottery_matches_tenant on public.lottery_matches for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.lottery_prizes enable row level security;

do $$ begin
   execute 'drop policy if exists lottery_prizes_tenant on public.lottery_prizes';
   execute 'create policy lottery_prizes_tenant on public.lottery_prizes for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.lottery_fund_uses enable row level security;

do $$ begin
   execute 'drop policy if exists lottery_fund_uses_tenant on public.lottery_fund_uses';
   execute 'create policy lottery_fund_uses_tenant on public.lottery_fund_uses for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.events enable row level security;

-- Policy hardening: events_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.event_proposals enable row level security;

-- Policy hardening: event_proposals_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.event_participants enable row level security;

do $$ begin
   execute 'drop policy if exists event_participants_tenant on public.event_participants';
   execute 'create policy event_participants_tenant on public.event_participants for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_guests enable row level security;

-- Policy hardening: event_guests_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.event_tasks enable row level security;

-- Policy hardening: event_tasks_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.event_task_assignees enable row level security;

-- Policy hardening: event_task_assignees_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.event_shifts enable row level security;

-- Policy hardening: event_shifts_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.event_shift_members enable row level security;

-- Policy hardening: event_shift_members_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.event_program enable row level security;

-- Policy hardening: event_program_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.event_routes enable row level security;

-- Policy hardening: event_routes_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.event_bands enable row level security;

-- Policy hardening: event_bands_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.event_exhibitors enable row level security;

-- Policy hardening: event_exhibitors_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.event_sponsors enable row level security;

-- Policy hardening: event_sponsors_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.event_documents enable row level security;

do $$ begin
   execute 'drop policy if exists event_documents_tenant on public.event_documents';
   execute 'create policy event_documents_tenant on public.event_documents for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_incidents enable row level security;

-- Policy hardening: event_incidents_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.event_octane_configs enable row level security;

-- Policy hardening: event_octane_configs_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.products enable row level security;

-- Policy hardening: products_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.product_variants enable row level security;

-- Policy hardening: product_variants_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.stock_locations enable row level security;

do $$ begin
   execute 'drop policy if exists stock_locations_tenant on public.stock_locations';
   execute 'create policy stock_locations_tenant on public.stock_locations for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.stock_lots enable row level security;

-- Policy hardening: stock_lots_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.stock_movements enable row level security;

-- Policy hardening: stock_movements_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.stock_reservations enable row level security;

-- Policy hardening: stock_reservations_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.physical_inventories enable row level security;

do $$ begin
   execute 'drop policy if exists physical_inventories_tenant on public.physical_inventories';
   execute 'create policy physical_inventories_tenant on public.physical_inventories for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.inventory_counts enable row level security;

do $$ begin
   execute 'drop policy if exists inventory_counts_tenant on public.inventory_counts';
   execute 'create policy inventory_counts_tenant on public.inventory_counts for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.external_customers enable row level security;

do $$ begin
   execute 'drop policy if exists external_customers_tenant on public.external_customers';
   execute 'create policy external_customers_tenant on public.external_customers for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.sales_orders enable row level security;

do $$ begin
   execute 'drop policy if exists sales_orders_tenant on public.sales_orders';
   execute 'create policy sales_orders_tenant on public.sales_orders for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.sales_order_lines enable row level security;

do $$ begin
   execute 'drop policy if exists sales_order_lines_tenant on public.sales_order_lines';
   execute 'create policy sales_order_lines_tenant on public.sales_order_lines for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.patch_delivery_requests enable row level security;

do $$ begin
   execute 'drop policy if exists patch_delivery_requests_tenant on public.patch_delivery_requests';
   execute 'create policy patch_delivery_requests_tenant on public.patch_delivery_requests for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.attachments enable row level security;

do $$ begin
   execute 'drop policy if exists attachments_tenant on public.attachments';
   execute 'create policy attachments_tenant on public.attachments for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.documents enable row level security;

do $$ begin
   execute 'drop policy if exists documents_tenant on public.documents';
   execute 'create policy documents_tenant on public.documents for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.document_versions enable row level security;

-- Final policy review: tenant FOR ALL bypassed private document ownership.
-- Later document_versions policies retain owner/manager access.

alter table public.document_links enable row level security;

-- Final policy review: tenant FOR ALL bypassed private document ownership.
-- Later document_links policies retain owner/manager access.

alter table public.document_approvals enable row level security;

-- Policy hardening: document_approvals_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.document_access_log enable row level security;

-- Policy hardening: document_access_log_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.document_ocr enable row level security;

-- Policy hardening: document_ocr_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.annual_books enable row level security;

-- Policy hardening: annual_books_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.annual_book_items enable row level security;

-- Policy hardening: annual_book_items_tenant omitted after individual before/after RLS proof.
-- Later versioned granular policies retain the legitimate direct/RPC contract.

alter table public.announcements enable row level security;

-- Final module policies are installed by later migrations.
-- A permissive FOR ALL tenant policy would bypass those permission checks.

alter table public.announcement_recipients enable row level security;

do $$ begin
   execute 'drop policy if exists announcement_recipients_tenant on public.announcement_recipients';
   execute 'create policy announcement_recipients_tenant on public.announcement_recipients for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

-- polls RLS is defined by its actual historical migration.

-- poll_options RLS is defined by its actual historical migration.

-- poll_votes RLS is defined by its actual historical migration.

alter table public.notifications enable row level security;

-- Final policy review: tenant FOR ALL exposed other recipients and allowed spoofing.
-- Later self-read/self-update policies retain the recipient contract.

alter table public.activity_feed enable row level security;

-- Final module policies are installed by later migrations.
-- A permissive FOR ALL tenant policy would bypass those permission checks.

alter table public.audit_log enable row level security;

do $$ begin
   execute 'drop policy if exists audit_log_tenant on public.audit_log';
   execute 'create policy audit_log_tenant on public.audit_log for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

-- imports RLS is defined by its actual historical migration.

-- import_rows RLS is defined by its actual historical migration.

-- exports RLS is defined with its actual historical table.

alter table public.scheduled_reports enable row level security;

do $$ begin
   execute 'drop policy if exists scheduled_reports_tenant on public.scheduled_reports';
   execute 'create policy scheduled_reports_tenant on public.scheduled_reports for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.payment_methods enable row level security;

do $$ begin
   execute 'drop policy if exists payment_methods_tenant on public.payment_methods';
   execute 'create policy payment_methods_tenant on public.payment_methods for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.number_sequences enable row level security;

do $$ begin
   execute 'drop policy if exists number_sequences_tenant on public.number_sequences';
   execute 'create policy number_sequences_tenant on public.number_sequences for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.consumption_card_templates enable row level security;

do $$ begin
   execute 'drop policy if exists consumption_card_templates_tenant on public.consumption_card_templates';
   execute 'create policy consumption_card_templates_tenant on public.consumption_card_templates for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.consumption_cards enable row level security;

do $$ begin
   execute 'drop policy if exists consumption_cards_tenant on public.consumption_cards';
   execute 'create policy consumption_cards_tenant on public.consumption_cards for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.consumption_card_scans enable row level security;

do $$ begin
   execute 'drop policy if exists consumption_card_scans_tenant on public.consumption_card_scans';
   execute 'create policy consumption_card_scans_tenant on public.consumption_card_scans for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.consumption_card_lines enable row level security;

do $$ begin
   execute 'drop policy if exists consumption_card_lines_tenant on public.consumption_card_lines';
   execute 'create policy consumption_card_lines_tenant on public.consumption_card_lines for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.clubhouse_visitors enable row level security;

do $$ begin
   execute 'drop policy if exists clubhouse_visitors_tenant on public.clubhouse_visitors';
   execute 'create policy clubhouse_visitors_tenant on public.clubhouse_visitors for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;


create or replace view public.v_member_fee_balances as
select m.club_id,m.id member_id,m.full_name,
 coalesce(sum(fo.amount),0) total_due,
 coalesce(sum(fo.paid_amount),0) total_paid,
 coalesce(sum(fo.amount-fo.paid_amount),0) outstanding
from public.members m left join public.fee_obligations fo on fo.member_id=m.id
group by m.club_id,m.id,m.full_name;

create or replace view public.v_stock_balances as
select pv.club_id,pv.id variant_id,p.name product_name,pv.sku,
 coalesce(sum(case when sm.movement_type in ('in','purchase','return','transfer_in') then sm.quantity else -sm.quantity end),0) quantity
from public.product_variants pv join public.products p on p.id=pv.product_id
left join public.stock_movements sm on sm.product_variant_id=pv.id
group by pv.club_id,pv.id,p.name,pv.sku;

create or replace view public.v_financial_balances as
select fa.club_id,fa.id account_id,fa.name,
 coalesce(fa.opening_balance,0)+coalesce(sum(case
  when ft.kind='income' and ft.account_id=fa.id then ft.amount
  when ft.kind='expense' and ft.account_id=fa.id then -ft.amount
  when ft.kind='transfer' and ft.account_id=fa.id then -ft.amount
  when ft.kind='transfer' and ft.destination_account_id=fa.id then ft.amount
  else 0 end),0) balance
from public.financial_accounts fa
left join public.financial_transactions ft on ft.account_id=fa.id or ft.destination_account_id=fa.id
group by fa.club_id,fa.id,fa.name,fa.opening_balance;

create or replace function public.dashboard_summary(target_club uuid)
returns jsonb language sql stable security definer set search_path=public as $$
select jsonb_build_object(
 'members', (select count(*) from public.members where club_id=target_club and status not in ('former','deceased')),
 'prospects', (select count(*) from public.members where club_id=target_club and status='prospect'),
 'total_balance', (select coalesce(sum(balance),0) from public.v_financial_balances where club_id=target_club),
 'fee_outstanding', (select coalesce(sum(outstanding),0) from public.v_member_fee_balances where club_id=target_club),
 'open_events', (select count(*) from public.events where club_id=target_club and status not in ('completed','cancelled','archived')),
 'low_stock', (select count(*) from public.v_stock_balances b join public.product_variants pv on pv.id=b.variant_id where b.club_id=target_club and b.quantity<=coalesce(pv.minimum_stock,0))
); $$;


-- Missing treasury bootstrap, exact current production columns captured 2026-10-14T15:12:17.705797+00:00.
-- Clean reconstruction only; this does not rename or reinterpret financial_* tables.
create type public."transaction_kind" as enum ('income','expense','transfer','reversal');
create table public."treasury_accounts" (
 "id" uuid default gen_random_uuid() not null,
 "club_id" uuid not null,
 "name" text not null,
 "account_type" text not null,
 "iban" text,
 "opening_balance" numeric(14,2) default 0 not null,
 "opening_date" date,
 "active" boolean default true not null,
 "created_at" timestamp with time zone default now() not null,
 "icon" text default '💰'::text not null,
 "allows_negative" boolean default false not null,
 "created_by" uuid default auth.uid(),
 "updated_at" timestamp with time zone default now(),
 "updated_by" uuid default auth.uid(),
 constraint "treasury_accounts_account_type_check" CHECK ((account_type = ANY (ARRAY['cash'::text, 'bank'::text, 'reserve'::text, 'fund'::text]))),
 constraint "treasury_accounts_club_id_name_key" UNIQUE (club_id, name),
 constraint "treasury_accounts_pkey" PRIMARY KEY (id)
);
alter table public."treasury_accounts" enable row level security;
create table public."treasury_categories" (
 "id" uuid default gen_random_uuid() not null,
 "club_id" uuid not null,
 "name" text not null,
 "direction" text not null,
 "active" boolean default true not null,
 "created_at" timestamp with time zone default now(),
 "created_by" uuid default auth.uid(),
 "updated_at" timestamp with time zone default now(),
 "updated_by" uuid default auth.uid(),
 constraint "treasury_categories_club_id_name_key" UNIQUE (club_id, name),
 constraint "treasury_categories_direction_check" CHECK ((direction = ANY (ARRAY['income'::text, 'expense'::text, 'both'::text]))),
 constraint "treasury_categories_pkey" PRIMARY KEY (id)
);
alter table public."treasury_categories" enable row level security;
create table public."treasury_transactions" (
 "id" uuid default gen_random_uuid() not null,
 "club_id" uuid not null,
 "kind" transaction_kind not null,
 "account_id" uuid not null,
 "destination_account_id" uuid,
 "category_id" uuid,
 "cost_center_id" uuid,
 "event_id" uuid,
 "transaction_date" date not null,
 "description" text not null,
 "amount" numeric(14,2) not null,
 "payment_method" text,
 "notes" text,
 "document_path" text,
 "source_type" text,
 "source_id" uuid,
 "reversal_of" uuid,
 "created_by" uuid default auth.uid(),
 "created_at" timestamp with time zone default now() not null,
 "updated_at" timestamp with time zone default now(),
 "updated_by" uuid default auth.uid()
 constraint "treasury_transactions_amount_check" CHECK ((amount > (0)::numeric)),
 constraint "treasury_transactions_check" CHECK ((((kind = 'transfer'::transaction_kind) AND (destination_account_id IS NOT NULL) AND (destination_account_id <> account_id)) OR ((kind <> 'transfer'::transaction_kind) AND (destination_account_id IS NULL)))),
 constraint "treasury_transactions_pkey" PRIMARY KEY (id)
);
alter table public."treasury_transactions" enable row level security;

-- Required fee enum captured from production, absent from historical bootstrap.
create type public.fee_status as enum ('pending','partial','paid','exempt','cancelled');

-- Required by the first fee SQL RPC; final FK remains in the versioned reconciliation migration.
alter table public.members add column profile_id uuid;


-- Exact baseline prerequisites of the next historical fee/lottery policies.
alter table public.fee_payments add column obligation_id uuid;
create table public."euromillions_draws" (
 "id" uuid default gen_random_uuid() not null,
 "club_id" uuid not null,
 "week" integer not null,
 "start_date" date,
 "end_date" date,
 "unit_cost" numeric(10,2) default 0 not null,
 "total_bet" numeric(12,2) default 0 not null,
 "prize" numeric(12,2) default 0 not null,
 "bulletin_path" text,
 "status" text default 'open'::text not null,
 "created_at" timestamp with time zone default now() not null,
 "created_by" uuid default auth.uid(),
 "updated_at" timestamp with time zone default now(),
 "updated_by" uuid default auth.uid(),
 constraint "euromillions_draws_club_id_week_start_date_key" UNIQUE (club_id, week, start_date),
 constraint "euromillions_draws_pkey" PRIMARY KEY (id),
 constraint "euromillions_draws_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text, 'paid'::text])))
);
alter table public."euromillions_draws" enable row level security;
-- Captured read contract is also required by the versioned child-table policies.
-- Do not restore euromillions_draws_access FOR ALL: it bypasses manageLottery.
create policy euromillions_read on public.euromillions_draws
for select to authenticated using (public.has_club_access(club_id));
create table public."euromillions_keys" (
 "id" uuid default gen_random_uuid() not null,
 "draw_id" uuid not null,
 "numbers" integer[] not null,
 "stars" integer[] not null,
 constraint "euromillions_keys_numbers_check" CHECK ((cardinality(numbers) = 5)),
 constraint "euromillions_keys_pkey" PRIMARY KEY (id),
 constraint "euromillions_keys_stars_check" CHECK ((cardinality(stars) = 2))
);
alter table public."euromillions_keys" enable row level security;
create table public."euromillions_participations" (
 "id" uuid default gen_random_uuid() not null,
 "draw_id" uuid not null,
 "member_id" uuid not null,
 "amount" numeric(10,2) default 0 not null,
 "paid" boolean default false not null,
 "paid_at" timestamp with time zone,
 "billing_frequency" text default 'weekly'::text not null,
 "numbers" integer[] default '{}'::integer[] not null,
 "stars" integer[] default '{}'::integer[] not null,
 "paid_amount" numeric default 0 not null,
 "balance" numeric default 0 not null,
 "active" boolean default true not null,
 "payment_method" text,
 "transaction_id" uuid,
 constraint "euromillions_participations_draw_id_member_id_key" UNIQUE (draw_id, member_id),
 constraint "euromillions_participations_pkey" PRIMARY KEY (id)
);
alter table public."euromillions_participations" enable row level security;


-- Remaining missing tables, exact captured production contracts used by historical policies/events.
create table public."domain_events" (
 "id" uuid default gen_random_uuid() not null,
 "club_id" uuid not null,
 "event_name" text not null,
 "aggregate_type" text not null,
 "aggregate_id" uuid,
 "actor_id" uuid,
 "payload" jsonb default '{}'::jsonb not null,
 "processed_at" timestamp with time zone,
 "created_at" timestamp with time zone default now() not null,
 constraint "domain_events_pkey" PRIMARY KEY (id)
);
alter table public."domain_events" enable row level security;
create table public."event_partners" (
 "id" uuid default gen_random_uuid() not null,
 "event_id" uuid not null,
 "partner_type" text not null,
 "name" text not null,
 "contact_name" text,
 "phone" text,
 "email" text,
 "agreed_value" numeric(12,2),
 "paid_value" numeric(12,2) default 0 not null,
 "notes" text,
 constraint "event_partners_partner_type_check" CHECK ((partner_type = ANY (ARRAY['band'::text, 'sponsor'::text, 'supplier'::text, 'exhibitor'::text, 'volunteer_team'::text]))),
 constraint "event_partners_pkey" PRIMARY KEY (id)
);
alter table public."event_partners" enable row level security;
create table public."event_registrations" (
 "id" uuid default gen_random_uuid() not null,
 "event_id" uuid not null,
 "member_id" uuid,
 "guest_name" text,
 "status" text default 'confirmed'::text not null,
 "checked_in_at" timestamp with time zone,
 "notes" text,
 "created_at" timestamp with time zone default now() not null,
 constraint "event_registrations_pkey" PRIMARY KEY (id)
);
alter table public."event_registrations" enable row level security;
create table public."member_motorcycles" (
 "id" uuid default gen_random_uuid() not null,
 "club_id" uuid not null,
 "member_id" uuid not null,
 "brand" text,
 "model" text,
 "year" integer,
 "registration" text,
 "nickname" text,
 "primary_motorcycle" boolean default false not null,
 "created_at" timestamp with time zone default now() not null,
 "created_by" uuid default auth.uid(),
 "updated_at" timestamp with time zone default now(),
 "updated_by" uuid default auth.uid(),
 "active" boolean default true not null,
 "acquired_on" date,
 "retired_on" date,
 "notes" text,
 constraint "member_motorcycles_pkey" PRIMARY KEY (id)
);
alter table public."member_motorcycles" enable row level security;

create type public.stock_movement_kind as enum ('purchase','sale','adjustment','loss','transfer','event_consumption','return');
alter table public.stock_movements add column created_by uuid default auth.uid();
CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;
alter table public.documents add column created_by uuid default auth.uid();
alter table public.documents add column storage_path text;
alter table public.audit_log add column actor_id uuid;
create type public.member_status as enum ('active','suspended','honorary','former','prospect','full_color','deceased');
alter table public.members add column joined_at date;
alter table public.activity_feed add column if not exists metadata jsonb default '{}'::jsonb not null;
alter table public.activity_feed add column if not exists activity_type text not null;
alter table public.products add column if not exists current_stock numeric(12,2) default 0 not null;
alter table public.products add column if not exists reserved_stock numeric default 0 not null;
alter table public.product_variants add column if not exists current_stock numeric(12,2) default 0 not null;
alter table public.product_variants add column if not exists reserved_stock numeric(12,2) default 0 not null;
alter table public.member_status_history add column if not exists changed_at timestamp with time zone default now() not null;
alter table public.member_status_history add column if not exists changed_by uuid default auth.uid();
alter table public.maintenance_records add column if not exists member_id uuid not null;
alter table public.maintenance_records add column if not exists motorcycle_id uuid not null;
alter table public.maintenance_records add column if not exists service_date date default CURRENT_DATE not null;
alter table public.maintenance_attachments add column maintenance_id uuid not null;
alter table public.member_patch_awards add column requested_at timestamp with time zone default now() not null;
alter table public.member_patch_awards add column status text default 'pending'::text not null;
alter table public.maintenance_attachments add column member_id uuid not null;
alter table public.member_patch_awards add column product_id uuid not null;
alter table public.member_patch_awards add column if not exists variant_id uuid;
alter table public.member_patch_awards add column if not exists inventory_location_id uuid;
alter table public.fee_payments add column paid_at timestamp with time zone default now() not null;
alter table public.fee_payment_allocations add column if not exists payment_id uuid not null;
alter table public.fee_payment_allocations add column if not exists obligation_id uuid not null;
alter table public.fee_payment_allocations add constraint fee_payment_allocations_payment_id_obligation_id_key unique(payment_id,obligation_id);
alter table public.fee_credits add column if not exists source_credit_id uuid;
alter table public.fee_credits add column if not exists reversal_of uuid;
-- fee_exemptions.obligation_id is declared in its canonical CREATE TABLE above.
-- reported_payments.proof_path is declared in its canonical CREATE TABLE above.
alter table public.event_guests add column registration_id uuid;
alter table public.event_routes add column active boolean default true not null;
-- event_bands.slot_start is declared in its canonical CREATE TABLE above.
alter table public.event_task_assignees add column member_id uuid;
alter table public.event_program add column sequence_no integer default 1 not null;
alter table public.event_program add column responsible_member_id uuid;
alter table public.event_incidents add column reported_by_member_id uuid;
alter table public.event_incidents add column assigned_member_id uuid;
alter table public.event_task_assignees add column event_id uuid not null;
alter table public.event_shift_members add column event_id uuid not null;
alter table public.event_proposals add column approved_event_id uuid;
-- Canonical document contract declared above.
-- Canonical document contract declared above.
-- Canonical document contract declared above.
-- Canonical document contract declared above.
alter table public.document_approvals add column requested_at timestamp with time zone default now() not null;
alter table public.document_ocr add column document_id uuid not null;
alter table public.annual_book_items add column sequence_no integer not null;
alter table public.annual_book_items add column document_id uuid;
alter table public.documents add column scope text default 'club'::text not null;
alter table public.documents add column owner_profile_id uuid;
alter table public.documents add column event_id uuid;
-- Canonical document contract declared above.
-- Canonical document contract declared above.
alter table public.annual_books add column cover_document_id uuid;
alter table public.document_ocr add column version_id uuid;
alter table public.document_access_log add column version_id uuid;
alter table public.stock_reservations add column product_id uuid not null;
alter table public.stock_reservations add column variant_id uuid;
alter table public.stock_reservations add column location_id uuid not null;
alter table public.stock_lots add column product_id uuid not null;
alter table public.stock_lots add column variant_id uuid;
alter table public.stock_lots add column status text default 'active'::text not null;
alter table public.stock_lots add column lot_code text not null;
alter table public.stock_reservations add column released_by uuid;
alter table public.products add column sale_price numeric(12,2) default 0 not null;

-- Foreign keys complete the captured missing prerequisite tables (all referenced tables exist here).
alter table public.domain_events add constraint "domain_events_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public.domain_events add constraint "domain_events_club_id_fkey" FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.euromillions_draws add constraint "euromillions_draws_club_id_fkey" FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.euromillions_keys add constraint "euromillions_keys_draw_id_fkey" FOREIGN KEY (draw_id) REFERENCES euromillions_draws(id) ON DELETE CASCADE;
alter table public.euromillions_participations add constraint "euromillions_participations_draw_id_fkey" FOREIGN KEY (draw_id) REFERENCES euromillions_draws(id) ON DELETE CASCADE;
alter table public.euromillions_participations add constraint "euromillions_participations_member_id_fkey" FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE;
alter table public.euromillions_participations add constraint "euromillions_participations_transaction_id_fkey" FOREIGN KEY (transaction_id) REFERENCES treasury_transactions(id);
alter table public.event_partners add constraint "event_partners_event_id_fkey" FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE;
alter table public.event_registrations add constraint "event_registrations_event_id_fkey" FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE;
alter table public.event_registrations add constraint "event_registrations_member_id_fkey" FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE SET NULL;
alter table public.member_motorcycles add constraint "member_motorcycles_club_id_fkey" FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.member_motorcycles add constraint "member_motorcycles_member_id_fkey" FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE;
alter table public.treasury_accounts add constraint "treasury_accounts_club_id_fkey" FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.treasury_categories add constraint "treasury_categories_club_id_fkey" FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.treasury_transactions add constraint "treasury_transactions_account_id_fkey" FOREIGN KEY (account_id) REFERENCES treasury_accounts(id);
alter table public.treasury_transactions add constraint "treasury_transactions_category_id_fkey" FOREIGN KEY (category_id) REFERENCES treasury_categories(id);
alter table public.treasury_transactions add constraint "treasury_transactions_club_id_fkey" FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.treasury_transactions add constraint "treasury_transactions_cost_center_id_fkey" FOREIGN KEY (cost_center_id) REFERENCES cost_centers(id);
alter table public.treasury_transactions add constraint "treasury_transactions_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(id);
alter table public.treasury_transactions add constraint "treasury_transactions_destination_account_id_fkey" FOREIGN KEY (destination_account_id) REFERENCES treasury_accounts(id);
alter table public.treasury_transactions add constraint "treasury_transactions_event_id_fkey" FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE SET NULL;
alter table public.treasury_transactions add constraint "treasury_transactions_reversal_of_fkey" FOREIGN KEY (reversal_of) REFERENCES treasury_transactions(id);
alter table public.activity_feed add column actor_id uuid;
alter table public.activity_feed add column entity_type text;
alter table public.activity_feed add column entity_id uuid;
alter table public.member_status_history add column old_status text;
alter table public.member_status_history add column new_status text not null;
alter table public.member_timeline add column source_type text;

-- Active identity/membership key contracts confirmed read-only in production.
alter table public.profiles add constraint "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.club_memberships add constraint "club_memberships_club_id_fkey" FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.club_memberships add constraint "club_memberships_club_id_profile_id_key" UNIQUE (club_id, profile_id);
alter table public.club_memberships add constraint "club_memberships_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
grant usage on schema public to authenticated;
grant select,insert,update,delete on all tables in schema public to authenticated;
grant usage,select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
insert into public.schema_migrations_bob(version,checksum) values('1.0.0-dev.1','generated-from-blueprint-v1') on conflict(version) do nothing;

-- Active bootstrap precedes every historical reference. Guard at file start limits this to a new schema.
-- Exact active contracts captured 2026-10-14; no legacy functions.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
-- Effective production type: reject drift; do not convert an existing populated schema.
do $$ begin
 if (select atttypid from pg_attribute where attrelid='public.profiles'::regclass and attname='email' and not attisdropped) is distinct from 'text'::regtype::oid then
  raise exception 'profiles.email must be production text; no automatic conversion' using errcode='55000';
 end if;
end $$;

do $bootstrap$ declare p pg_proc%rowtype; begin
 select * into p from pg_proc where oid=to_regprocedure('public.handle_new_user()');
 if found then
  if not p.prosecdef or p.provolatile<>'v' or p.proisstrict or p.proparallel<>'u' or p.proretset
    or p.prorettype<>'trigger'::regtype or pg_get_userbyid(p.proowner)<>'postgres'
    or (select lanname from pg_language where oid=p.prolang)<>'plpgsql'
    or pg_get_function_arguments(p.oid)<>''
    or p.proconfig is distinct from array['search_path=public']::text[] or md5(replace(p.prosrc,E'\r\n',E'\n'))<>'d09d2d62677178915cf6911a86adb79a' then
   raise exception 'Unreviewed handle_new_user contract' using errcode='55000';
  end if;
 else
  execute $ddl$CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.profiles (
    id,
    full_name,
    email
  )
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'full_name',
      split_part(new.email, '@', 1)
    ),
    new.email
  )
  on conflict (id) do nothing;

  return new;
end;
$function$;$ddl$;
  revoke all on function public.handle_new_user() from public,anon,authenticated,service_role;
  grant execute on function public.handle_new_user() to service_role;
 end if;
end $bootstrap$;

do $bootstrap$ declare p pg_proc%rowtype; begin
 select * into p from pg_proc where oid=to_regprocedure('public.has_club_role(uuid,text[])');
 if found then
  if not p.prosecdef or p.provolatile<>'s' or p.proisstrict or p.proparallel<>'u' or p.proretset
    or p.prorettype<>'boolean'::regtype or pg_get_userbyid(p.proowner)<>'postgres'
    or (select lanname from pg_language where oid=p.prolang)<>'sql'
    or pg_get_function_arguments(p.oid)<>'target_club uuid, allowed_roles text[]'
    or p.proconfig is distinct from array['search_path=public']::text[] or md5(replace(p.prosrc,E'\r\n',E'\n'))<>'d20dbc0bc410cd7afe5b584d9311dfba' then
   raise exception 'Unreviewed has_club_role contract' using errcode='55000';
  end if;
 else
  execute $ddl$CREATE OR REPLACE FUNCTION public.has_club_role(target_club uuid, allowed_roles text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.club_memberships
    where club_id = target_club
      and profile_id = auth.uid()
      and active = true
      and access_role = any(allowed_roles)
  );
$function$;$ddl$;
  revoke all on function public.has_club_role(uuid,text[]) from public,anon,authenticated,service_role;
  grant execute on function public.has_club_role(uuid,text[]) to authenticated,service_role;
 end if;
end $bootstrap$;

do $trigger$ declare t pg_trigger%rowtype; begin
 select * into t from pg_trigger where tgrelid='auth.users'::regclass and tgname='on_auth_user_created' and not tgisinternal;
 if found then
  if t.tgfoid<>to_regprocedure('public.handle_new_user()') or t.tgtype<>5 or t.tgenabled<>'O' or t.tgqual is not null or t.tgnargs<>0 then
   raise exception 'Unreviewed Auth onboarding trigger' using errcode='55000';
  end if;
 else
  create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
 end if;
end $trigger$;
-- Fresh-baseline contracts used by later versioned writers. This migration's
-- empty-schema guard forbids using these declarations as a production backfill.
-- Evidence: fees redesign/operational schema, inventory advanced schema,
-- shop variants and captured production catalog (policy hardening review).
alter table public.fee_obligations
  add column reference_year integer not null,
  add column reference_month integer,
  add column notes text,
  add constraint fee_obligations_club_id_member_id_reference_year_reference__key
    unique(club_id,member_id,reference_year,reference_month),
  add constraint fee_obligations_club_id_fkey foreign key(club_id) references public.clubs(id) on delete cascade,
  add constraint fee_obligations_fee_plan_id_fkey foreign key(fee_plan_id) references public.fee_plans(id),
  add constraint fee_obligations_amount_check check(amount>=0),
  add constraint fee_obligations_paid_amount_check check(paid_amount>=0);
alter table public.fee_obligations
  alter column member_id set not null,
  alter column amount set not null,
  alter column paid_amount set not null,
  alter column status set default 'pending',
  alter column status set not null;

alter table public.stock_movements
  add column product_id uuid not null references public.products(id) on delete cascade,
  add column variant_id uuid references public.product_variants(id) on delete set null,
  add column kind public.stock_movement_kind not null,
  add column notes text,
  add constraint stock_movements_club_id_fkey foreign key(club_id) references public.clubs(id) on delete cascade;
alter table public.stock_movements alter column quantity set not null;
alter table public.stock_movements
  add constraint stock_movements_created_by_fkey foreign key(created_by) references public.profiles(id),
  add constraint stock_movements_event_id_fkey foreign key(event_id) references public.events(id) on delete set null;
alter table public.product_variants add column name text not null;
-- inventory_count_start/finalize and lot receive read p.cost explicitly.
alter table public.products add column cost numeric(12,2) not null default 0;

alter table public.stock_lots
  add column initial_quantity numeric(12,2) not null,
  add column created_by uuid default auth.uid(),
  add column supplier text,
  add column notes text,
  add constraint stock_lots_initial_quantity_check check(initial_quantity>0),
  add constraint stock_lots_quantity_check check(quantity>=0),
  add constraint stock_lots_check check(quantity<=initial_quantity),
  add constraint stock_lots_unit_cost_check check(unit_cost is null or unit_cost>=0),
  add constraint stock_lots_status_check check(status in ('active','expired','depleted','quarantined'));
alter table public.stock_lots
  alter column location_id set not null,
  alter column received_at set default current_date,
  alter column received_at set not null,
  alter column quantity set not null;
alter table public.stock_lots
  add constraint stock_lots_club_id_fkey foreign key(club_id) references public.clubs(id) on delete cascade,
  add constraint stock_lots_product_id_fkey foreign key(product_id) references public.products(id) on delete restrict,
  add constraint stock_lots_variant_id_fkey foreign key(variant_id) references public.product_variants(id) on delete restrict,
  add constraint stock_lots_created_by_fkey foreign key(created_by) references public.profiles(id) on delete set null;
alter table public.stock_reservations
  add column released_at timestamptz,
  add column created_by uuid default auth.uid(),
  add column release_reason text,
  add column notes text,
  add constraint stock_reservations_quantity_check check(quantity>0),
  add constraint stock_reservations_status_check check(status in ('active','released','cancelled','expired')),
  add constraint stock_reservations_check check(expires_at>reserved_at and expires_at<=reserved_at+interval '30 days');
alter table public.stock_reservations
  alter column member_id set not null,
  alter column quantity set not null,
  alter column status set default 'active',
  alter column status set not null,
  alter column reserved_at set default now(),
  alter column reserved_at set not null,
  alter column expires_at set default now()+interval '30 days',
  alter column expires_at set not null;
alter table public.stock_reservations
  add constraint stock_reservations_club_id_fkey foreign key(club_id) references public.clubs(id) on delete cascade,
  add constraint stock_reservations_product_id_fkey foreign key(product_id) references public.products(id) on delete restrict,
  add constraint stock_reservations_variant_id_fkey foreign key(variant_id) references public.product_variants(id) on delete restrict,
  add constraint stock_reservations_member_id_fkey foreign key(member_id) references public.members(id) on delete restrict,
  add constraint stock_reservations_released_by_fkey foreign key(released_by) references public.profiles(id) on delete set null,
  add constraint stock_reservations_created_by_fkey foreign key(created_by) references public.profiles(id) on delete set null;

alter table public.fee_payments
  add column received_by uuid references public.profiles(id),
  add column notes text,
  add constraint fee_payments_club_id_fkey foreign key(club_id) references public.clubs(id) on delete cascade,
  add constraint fee_payments_member_id_fkey foreign key(member_id) references public.members(id),
  add constraint fee_payments_obligation_id_fkey foreign key(obligation_id) references public.fee_obligations(id) on delete cascade,
  add constraint fee_payments_transaction_id_fkey foreign key(transaction_id) references public.treasury_transactions(id),
  add constraint fee_payments_amount_check check(amount>0);
alter table public.fee_payments alter column amount set not null;
-- member_id becomes NOT NULL in the existing operational migration.
alter table public.fee_payment_allocations
  add constraint fee_payment_allocations_club_id_fkey foreign key(club_id) references public.clubs(id) on delete cascade,
  add constraint fee_payment_allocations_payment_id_fkey foreign key(payment_id) references public.fee_payments(id) on delete restrict,
  add constraint fee_payment_allocations_obligation_id_fkey foreign key(obligation_id) references public.fee_obligations(id) on delete restrict,
  add constraint fee_payment_allocations_amount_check check(amount>0);
alter table public.fee_payment_allocations alter column amount set not null;
-- Inventory writer, export and bar read model contract; captured production types/defaults.
-- Only empty-schema baseline; no populated-schema conversion.
alter table public.products
  add column sku text,
  add column unit text not null default 'unit',
  add column minimum_stock numeric(12,2) not null default 0;
-- Structural blockers: empty-schema baseline only; production catalog + active writers.
alter table public.notifications
  add column notification_type text not null default 'info',
  alter column body set not null,
  alter column priority set default 'normal',
  alter column priority set not null;
-- Extra blueprint field is not part of the canonical writer. Keep optional legacy
-- input/audit behavior; tenant authorization continues through the parent product.
alter table public.product_variants alter column club_id drop not null;
-- Membership roles are written by the privileged user-access-admin Edge path.
-- Never grant tenant members direct role writes; reproduced self escalation.
create policy memberships_access on public.club_memberships for select to authenticated
 using ((profile_id = auth.uid()) OR public.has_club_access(club_id));
create policy memberships_read on public.club_memberships for select to authenticated
 using ((profile_id = auth.uid()) OR public.has_club_role(club_id, ARRAY['admin'::text, 'super_admin'::text]));
-- Consolidated review: canonical writers require these captured production fields.
-- Baseline only: later CREATE TABLE IF NOT EXISTS cannot add omitted columns.
-- OCR fields agree with 20260814112515; event contracts with captured catalog.
alter table public.document_ocr
  add column provider text,
  add column model text,
  add column raw_text text,
  add column error_message text,
  add column started_at timestamptz,
  add column completed_at timestamptz;
alter table public.events
  add column budget numeric(14,2) not null default 0,
  add column banner_path text,
  add column event_mode_enabled boolean not null default false;
-- High-risk semantic repairs: clean reconstruction only; no production migration.
create table if not exists public.inventory_locations (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  name text not null, description text, active boolean not null default true, created_at timestamptz not null default now(),
  unique(club_id,name)
);
create type public.event_status as enum ('draft','published','active','completed','cancelled');
create type public.payment_status as enum ('paid','pending','exempt');
create type public.transaction_type as enum ('income','expense');
create type public.user_role as enum ('member','treasurer','admin','super_admin');
alter table public.announcements add column if not exists body text;
alter table public.announcements alter column body drop default;
alter table public.announcements alter column body set not null;
alter table public.announcements add column if not exists priority text default 'normal'::text;
alter table public.announcements alter column priority set default 'normal'::text;
alter table public.announcements alter column priority set not null;
alter table public.announcements add column if not exists audience text default 'all'::text;
alter table public.announcements alter column audience set default 'all'::text;
alter table public.announcements alter column audience set not null;
alter table public.announcements add column if not exists published_at timestamp with time zone default now();
alter table public.announcements alter column published_at set default now();
alter table public.announcements alter column published_at set not null;
alter table public.announcements add column if not exists requires_acknowledgement boolean default false;
alter table public.announcements alter column requires_acknowledgement set default false;
alter table public.announcements alter column requires_acknowledgement set not null;
alter table public.announcements add column if not exists created_at timestamp with time zone default now();
alter table public.announcements alter column created_at set default now();
alter table public.announcements alter column created_at set not null;
alter table public.announcements add column if not exists updated_at timestamp with time zone default now();
alter table public.announcements alter column updated_at set default now();
alter table public.announcements alter column updated_at set not null;
alter table public.announcements add constraint announcements_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.announcements add constraint announcements_expiry_after_publication CHECK (((expires_at IS NULL) OR (expires_at > published_at)));
alter table public.announcements add constraint announcements_priority_check CHECK ((priority = ANY (ARRAY['informative'::text, 'normal'::text, 'important'::text, 'urgent'::text, 'critical'::text])));
alter table public.annual_book_items add column if not exists annual_book_id uuid;
alter table public.annual_book_items alter column annual_book_id drop default;
alter table public.annual_book_items alter column annual_book_id set not null;
alter table public.annual_book_items add column if not exists item_type text default 'custom'::text;
alter table public.annual_book_items alter column item_type set default 'custom'::text;
alter table public.annual_book_items alter column item_type set not null;
alter table public.annual_book_items add column if not exists linked_entity_type text;
alter table public.annual_book_items alter column linked_entity_type drop default;
alter table public.annual_book_items alter column linked_entity_type drop not null;
alter table public.annual_book_items add column if not exists linked_entity_id uuid;
alter table public.annual_book_items alter column linked_entity_id drop default;
alter table public.annual_book_items alter column linked_entity_id drop not null;
alter table public.annual_book_items add column if not exists event_date date;
alter table public.annual_book_items alter column event_date drop default;
alter table public.annual_book_items alter column event_date drop not null;
alter table public.annual_book_items add column if not exists created_at timestamp with time zone default now();
alter table public.annual_book_items alter column created_at set default now();
alter table public.annual_book_items alter column created_at set not null;
alter table public.annual_book_items add column if not exists updated_at timestamp with time zone default now();
alter table public.annual_book_items alter column updated_at set default now();
alter table public.annual_book_items alter column updated_at set not null;
alter table public.annual_book_items add constraint annual_book_items_annual_book_id_fkey FOREIGN KEY (annual_book_id) REFERENCES annual_books(id) ON DELETE CASCADE;
alter table public.annual_book_items add constraint annual_book_items_annual_book_id_sequence_no_key UNIQUE (annual_book_id, sequence_no);
alter table public.annual_book_items add constraint annual_book_items_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE SET NULL;
alter table public.annual_book_items add constraint annual_book_items_item_type_check CHECK ((item_type = ANY (ARRAY['custom'::text, 'document'::text, 'event'::text, 'member'::text, 'timeline'::text])));
alter table public.annual_book_items add constraint annual_book_items_sequence_no_check CHECK ((sequence_no > 0));
alter table public.annual_books add column if not exists year integer;
alter table public.annual_books alter column year drop default;
alter table public.annual_books alter column year set not null;
alter table public.annual_books add column if not exists description text;
alter table public.annual_books alter column description drop default;
alter table public.annual_books alter column description drop not null;
alter table public.annual_books add column if not exists status text default 'draft'::text;
alter table public.annual_books alter column status set default 'draft'::text;
alter table public.annual_books alter column status set not null;
alter table public.annual_books add column if not exists published_at timestamp with time zone;
alter table public.annual_books alter column published_at drop default;
alter table public.annual_books alter column published_at drop not null;
alter table public.annual_books add column if not exists created_at timestamp with time zone default now();
alter table public.annual_books alter column created_at set default now();
alter table public.annual_books alter column created_at set not null;
alter table public.annual_books add column if not exists updated_at timestamp with time zone default now();
alter table public.annual_books alter column updated_at set default now();
alter table public.annual_books alter column updated_at set not null;
alter table public.annual_books add constraint annual_books_club_id_year_key UNIQUE (club_id, year);
alter table public.annual_books add constraint annual_books_cover_document_id_fkey FOREIGN KEY (cover_document_id) REFERENCES documents(id) ON DELETE SET NULL;
alter table public.annual_books add constraint annual_books_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text, 'archived'::text])));
alter table public.annual_books add constraint annual_books_year_check CHECK (((year >= 2000) AND (year <= 2200)));
alter table public.document_access_log add column if not exists id uuid default gen_random_uuid();
alter table public.document_access_log alter column id set default gen_random_uuid();
alter table public.document_access_log alter column id set not null;
alter table public.document_access_log add column if not exists document_id uuid;
alter table public.document_access_log alter column document_id drop default;
alter table public.document_access_log alter column document_id set not null;
alter table public.document_access_log add column if not exists profile_id uuid default auth.uid();
alter table public.document_access_log alter column profile_id set default auth.uid();
alter table public.document_access_log alter column profile_id set not null;
alter table public.document_access_log add column if not exists action text;
alter table public.document_access_log alter column action drop default;
alter table public.document_access_log alter column action set not null;
alter table public.document_access_log add column if not exists metadata jsonb default '{}'::jsonb;
alter table public.document_access_log alter column metadata set default '{}'::jsonb;
alter table public.document_access_log alter column metadata set not null;
alter table public.document_access_log add constraint document_access_log_action_check CHECK ((action = ANY (ARRAY['view'::text, 'download'::text, 'signed_url'::text, 'share'::text])));
alter table public.document_access_log add constraint document_access_log_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE;
alter table public.document_access_log add constraint document_access_log_version_id_fkey FOREIGN KEY (version_id) REFERENCES document_versions(id) ON DELETE SET NULL;
alter table public.document_approvals add column if not exists document_id uuid;
alter table public.document_approvals alter column document_id drop default;
alter table public.document_approvals alter column document_id set not null;
alter table public.document_approvals add column if not exists status text default 'pending'::text;
alter table public.document_approvals alter column status set default 'pending'::text;
alter table public.document_approvals alter column status set not null;
alter table public.document_approvals add column if not exists requested_by uuid default auth.uid();
alter table public.document_approvals alter column requested_by set default auth.uid();
alter table public.document_approvals alter column requested_by set not null;
alter table public.document_approvals add column if not exists decided_by uuid;
alter table public.document_approvals alter column decided_by drop default;
alter table public.document_approvals alter column decided_by drop not null;
alter table public.document_approvals add column if not exists decided_at timestamp with time zone;
alter table public.document_approvals alter column decided_at drop default;
alter table public.document_approvals alter column decided_at drop not null;
alter table public.document_approvals add column if not exists notes text;
alter table public.document_approvals alter column notes drop default;
alter table public.document_approvals alter column notes drop not null;
alter table public.document_approvals add column if not exists created_at timestamp with time zone default now();
alter table public.document_approvals alter column created_at set default now();
alter table public.document_approvals alter column created_at set not null;
alter table public.document_approvals add column if not exists updated_at timestamp with time zone default now();
alter table public.document_approvals alter column updated_at set default now();
alter table public.document_approvals alter column updated_at set not null;
alter table public.document_approvals add constraint document_approvals_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE;
alter table public.document_approvals add constraint document_approvals_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text])));
alter table public.document_ocr add column if not exists status text default 'pending'::text;
alter table public.document_ocr alter column status set default 'pending'::text;
alter table public.document_ocr alter column status set not null;
alter table public.document_ocr add column if not exists confidence numeric(5,4);
alter table public.document_ocr alter column confidence type numeric(5,4) using confidence::numeric(5,4);
alter table public.document_ocr alter column confidence drop default;
alter table public.document_ocr alter column confidence drop not null;
alter table public.document_ocr add column if not exists created_by uuid default auth.uid();
alter table public.document_ocr alter column created_by set default auth.uid();
alter table public.document_ocr alter column created_by set not null;
alter table public.document_ocr add column if not exists created_at timestamp with time zone default now();
alter table public.document_ocr alter column created_at set default now();
alter table public.document_ocr alter column created_at set not null;
alter table public.document_ocr add column if not exists updated_at timestamp with time zone default now();
alter table public.document_ocr alter column updated_at set default now();
alter table public.document_ocr alter column updated_at set not null;
alter table public.document_ocr add constraint document_ocr_confidence_check CHECK (((confidence IS NULL) OR ((confidence >= (0)::numeric) AND (confidence <= (1)::numeric))));
alter table public.document_ocr add constraint document_ocr_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE;
alter table public.document_ocr add constraint document_ocr_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'ready'::text, 'unconfigured'::text, 'failed'::text, 'cancelled'::text])));
alter table public.document_ocr add constraint document_ocr_version_id_fkey FOREIGN KEY (version_id) REFERENCES document_versions(id) ON DELETE SET NULL;
alter table public.event_guests add column if not exists event_id uuid;
alter table public.event_guests alter column event_id drop default;
alter table public.event_guests alter column event_id set not null;
alter table public.event_guests add column if not exists host_member_id uuid;
alter table public.event_guests alter column host_member_id drop default;
alter table public.event_guests alter column host_member_id set not null;
alter table public.event_guests add column if not exists status text default 'confirmed'::text;
alter table public.event_guests alter column status set default 'confirmed'::text;
alter table public.event_guests alter column status set not null;
alter table public.event_guests add column if not exists checked_in_at timestamp with time zone;
alter table public.event_guests alter column checked_in_at drop default;
alter table public.event_guests alter column checked_in_at drop not null;
alter table public.event_guests add column if not exists created_at timestamp with time zone default now();
alter table public.event_guests alter column created_at set default now();
alter table public.event_guests alter column created_at set not null;
alter table public.event_guests add column if not exists updated_at timestamp with time zone default now();
alter table public.event_guests alter column updated_at set default now();
alter table public.event_guests alter column updated_at set not null;
alter table public.event_guests add constraint event_guests_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE;
alter table public.event_guests add constraint event_guests_host_member_id_fkey FOREIGN KEY (host_member_id) REFERENCES members(id) ON DELETE CASCADE;
alter table public.event_guests add constraint event_guests_registration_id_fkey FOREIGN KEY (registration_id) REFERENCES event_registrations(id) ON DELETE SET NULL;
alter table public.event_guests add constraint event_guests_status_check CHECK ((status = ANY (ARRAY['confirmed'::text, 'cancelled'::text, 'checked_in'::text])));
alter table public.event_incidents add column if not exists event_id uuid;
alter table public.event_incidents alter column event_id drop default;
alter table public.event_incidents alter column event_id set not null;
alter table public.event_incidents add column if not exists occurred_at timestamp with time zone default now();
alter table public.event_incidents alter column occurred_at set default now();
alter table public.event_incidents alter column occurred_at set not null;
alter table public.event_incidents add column if not exists title text;
alter table public.event_incidents alter column title drop default;
alter table public.event_incidents alter column title set not null;
alter table public.event_incidents add column if not exists severity text default 'low'::text;
alter table public.event_incidents alter column severity set default 'low'::text;
alter table public.event_incidents alter column severity set not null;
alter table public.event_incidents add column if not exists status text default 'open'::text;
alter table public.event_incidents alter column status set default 'open'::text;
alter table public.event_incidents alter column status set not null;
alter table public.event_incidents add column if not exists resolution text;
alter table public.event_incidents alter column resolution drop default;
alter table public.event_incidents alter column resolution drop not null;
alter table public.event_incidents add column if not exists resolved_at timestamp with time zone;
alter table public.event_incidents alter column resolved_at drop default;
alter table public.event_incidents alter column resolved_at drop not null;
alter table public.event_incidents add column if not exists created_at timestamp with time zone default now();
alter table public.event_incidents alter column created_at set default now();
alter table public.event_incidents alter column created_at set not null;
alter table public.event_incidents add column if not exists updated_at timestamp with time zone default now();
alter table public.event_incidents alter column updated_at set default now();
alter table public.event_incidents alter column updated_at set not null;
alter table public.event_incidents add constraint event_incidents_assigned_member_id_fkey FOREIGN KEY (assigned_member_id) REFERENCES members(id) ON DELETE SET NULL;
alter table public.event_incidents add constraint event_incidents_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE;
alter table public.event_incidents add constraint event_incidents_reported_by_member_id_fkey FOREIGN KEY (reported_by_member_id) REFERENCES members(id) ON DELETE SET NULL;
alter table public.event_incidents add constraint event_incidents_severity_check CHECK ((severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])));
alter table public.event_incidents add constraint event_incidents_status_check CHECK ((status = ANY (ARRAY['open'::text, 'monitoring'::text, 'resolved'::text, 'closed'::text])));
alter table public.event_octane_configs add column if not exists event_id uuid;
alter table public.event_octane_configs alter column event_id drop default;
alter table public.event_octane_configs alter column event_id set not null;
alter table public.event_octane_configs add column if not exists unit_price numeric(10,2) default 1.50;
alter table public.event_octane_configs alter column unit_price set default 1.50;
alter table public.event_octane_configs alter column unit_price set not null;
alter table public.event_octane_configs add column if not exists five_card_units integer default 5;
alter table public.event_octane_configs alter column five_card_units set default 5;
alter table public.event_octane_configs alter column five_card_units set not null;
alter table public.event_octane_configs add column if not exists five_card_price numeric(10,2) default 7.00;
alter table public.event_octane_configs alter column five_card_price set default 7.00;
alter table public.event_octane_configs alter column five_card_price set not null;
alter table public.event_octane_configs add column if not exists ten_card_units integer default 10;
alter table public.event_octane_configs alter column ten_card_units set default 10;
alter table public.event_octane_configs alter column ten_card_units set not null;
alter table public.event_octane_configs add column if not exists ten_card_price numeric(10,2) default 13.00;
alter table public.event_octane_configs alter column ten_card_price set default 13.00;
alter table public.event_octane_configs alter column ten_card_price set not null;
alter table public.event_octane_configs add column if not exists ten_card_bonus integer default 1;
alter table public.event_octane_configs alter column ten_card_bonus set default 1;
alter table public.event_octane_configs alter column ten_card_bonus set not null;
alter table public.event_octane_configs add column if not exists product_rules jsonb default '{}'::jsonb;
alter table public.event_octane_configs alter column product_rules set default '{}'::jsonb;
alter table public.event_octane_configs alter column product_rules set not null;
alter table public.event_octane_configs add column if not exists active boolean default true;
alter table public.event_octane_configs alter column active set default true;
alter table public.event_octane_configs alter column active set not null;
alter table public.event_octane_configs add column if not exists notes text;
alter table public.event_octane_configs alter column notes drop default;
alter table public.event_octane_configs alter column notes drop not null;
alter table public.event_octane_configs add column if not exists created_at timestamp with time zone default now();
alter table public.event_octane_configs alter column created_at set default now();
alter table public.event_octane_configs alter column created_at set not null;
alter table public.event_octane_configs add column if not exists updated_at timestamp with time zone default now();
alter table public.event_octane_configs alter column updated_at set default now();
alter table public.event_octane_configs alter column updated_at set not null;
alter table public.event_octane_configs add constraint event_octane_configs_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE;
alter table public.event_octane_configs add constraint event_octane_configs_event_id_key UNIQUE (event_id);
alter table public.event_octane_configs add constraint event_octane_configs_five_card_price_check CHECK ((five_card_price >= (0)::numeric));
alter table public.event_octane_configs add constraint event_octane_configs_five_card_units_check CHECK ((five_card_units > 0));
alter table public.event_octane_configs add constraint event_octane_configs_ten_card_bonus_check CHECK ((ten_card_bonus >= 0));
alter table public.event_octane_configs add constraint event_octane_configs_ten_card_price_check CHECK ((ten_card_price >= (0)::numeric));
alter table public.event_octane_configs add constraint event_octane_configs_ten_card_units_check CHECK ((ten_card_units > 0));
alter table public.event_octane_configs add constraint event_octane_configs_unit_price_check CHECK ((unit_price >= (0)::numeric));
alter table public.event_program add column if not exists event_id uuid;
alter table public.event_program alter column event_id drop default;
alter table public.event_program alter column event_id set not null;
alter table public.event_program add column if not exists item_type text default 'activity'::text;
alter table public.event_program alter column item_type set default 'activity'::text;
alter table public.event_program alter column item_type set not null;
alter table public.event_program add column if not exists notes text;
alter table public.event_program alter column notes drop default;
alter table public.event_program alter column notes drop not null;
alter table public.event_program add column if not exists created_at timestamp with time zone default now();
alter table public.event_program alter column created_at set default now();
alter table public.event_program alter column created_at set not null;
alter table public.event_program add column if not exists updated_at timestamp with time zone default now();
alter table public.event_program alter column updated_at set default now();
alter table public.event_program alter column updated_at set not null;
alter table public.event_program add constraint event_program_dates_check CHECK (((ends_at IS NULL) OR (starts_at IS NULL) OR (ends_at >= starts_at)));
alter table public.event_program add constraint event_program_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE;
alter table public.event_program add constraint event_program_event_id_sequence_no_key UNIQUE (event_id, sequence_no);
alter table public.event_program add constraint event_program_responsible_member_id_fkey FOREIGN KEY (responsible_member_id) REFERENCES members(id) ON DELETE SET NULL;
alter table public.event_program add constraint event_program_sequence_no_check CHECK ((sequence_no > 0));
alter table public.event_proposals add column if not exists proposed_by uuid;
alter table public.event_proposals alter column proposed_by drop default;
alter table public.event_proposals alter column proposed_by set not null;
alter table public.event_proposals add column if not exists name text;
alter table public.event_proposals alter column name drop default;
alter table public.event_proposals alter column name set not null;
alter table public.event_proposals add column if not exists description text;
alter table public.event_proposals alter column description drop default;
alter table public.event_proposals alter column description drop not null;
alter table public.event_proposals add column if not exists location text;
alter table public.event_proposals alter column location drop default;
alter table public.event_proposals alter column location drop not null;
alter table public.event_proposals add column if not exists starts_at timestamp with time zone;
alter table public.event_proposals alter column starts_at drop default;
alter table public.event_proposals alter column starts_at drop not null;
alter table public.event_proposals add column if not exists ends_at timestamp with time zone;
alter table public.event_proposals alter column ends_at drop default;
alter table public.event_proposals alter column ends_at drop not null;
alter table public.event_proposals add column if not exists event_kind text default 'general'::text;
alter table public.event_proposals alter column event_kind set default 'general'::text;
alter table public.event_proposals alter column event_kind set not null;
alter table public.event_proposals add column if not exists status text default 'submitted'::text;
alter table public.event_proposals alter column status set default 'submitted'::text;
alter table public.event_proposals alter column status set not null;
alter table public.event_proposals add column if not exists decision_notes text;
alter table public.event_proposals alter column decision_notes drop default;
alter table public.event_proposals alter column decision_notes drop not null;
alter table public.event_proposals add column if not exists decided_by uuid;
alter table public.event_proposals alter column decided_by drop default;
alter table public.event_proposals alter column decided_by drop not null;
alter table public.event_proposals add column if not exists decided_at timestamp with time zone;
alter table public.event_proposals alter column decided_at drop default;
alter table public.event_proposals alter column decided_at drop not null;
alter table public.event_proposals add column if not exists created_at timestamp with time zone default now();
alter table public.event_proposals alter column created_at set default now();
alter table public.event_proposals alter column created_at set not null;
alter table public.event_proposals add column if not exists updated_at timestamp with time zone default now();
alter table public.event_proposals alter column updated_at set default now();
alter table public.event_proposals alter column updated_at set not null;
alter table public.event_proposals add constraint event_proposals_approved_event_id_fkey FOREIGN KEY (approved_event_id) REFERENCES events(id) ON DELETE SET NULL;
alter table public.event_proposals add constraint event_proposals_dates_check CHECK (((ends_at IS NULL) OR (starts_at IS NULL) OR (ends_at >= starts_at)));
alter table public.event_proposals add constraint event_proposals_event_kind_check CHECK ((event_kind = ANY (ARRAY['general'::text, 'ride'::text, 'rock_ride_in'::text])));
alter table public.event_proposals add constraint event_proposals_status_check CHECK ((status = ANY (ARRAY['submitted'::text, 'approved'::text, 'rejected'::text, 'withdrawn'::text])));
alter table public.event_routes add column if not exists event_id uuid;
alter table public.event_routes alter column event_id drop default;
alter table public.event_routes alter column event_id set not null;
alter table public.event_routes add column if not exists name text default 'Roadbook'::text;
alter table public.event_routes alter column name set default 'Roadbook'::text;
alter table public.event_routes alter column name set not null;
alter table public.event_routes add column if not exists start_location text;
alter table public.event_routes alter column start_location drop default;
alter table public.event_routes alter column start_location drop not null;
alter table public.event_routes add column if not exists end_location text;
alter table public.event_routes alter column end_location drop default;
alter table public.event_routes alter column end_location drop not null;
alter table public.event_routes add column if not exists distance_km numeric(10,2);
alter table public.event_routes alter column distance_km type numeric(10,2) using distance_km::numeric(10,2);
alter table public.event_routes alter column distance_km drop default;
alter table public.event_routes alter column distance_km drop not null;
alter table public.event_routes add column if not exists estimated_minutes integer;
alter table public.event_routes alter column estimated_minutes drop default;
alter table public.event_routes alter column estimated_minutes drop not null;
alter table public.event_routes add column if not exists notes text;
alter table public.event_routes alter column notes drop default;
alter table public.event_routes alter column notes drop not null;
alter table public.event_routes add column if not exists emergency_notes text;
alter table public.event_routes alter column emergency_notes drop default;
alter table public.event_routes alter column emergency_notes drop not null;
alter table public.event_routes add column if not exists created_at timestamp with time zone default now();
alter table public.event_routes alter column created_at set default now();
alter table public.event_routes alter column created_at set not null;
alter table public.event_routes add column if not exists updated_at timestamp with time zone default now();
alter table public.event_routes alter column updated_at set default now();
alter table public.event_routes alter column updated_at set not null;
alter table public.event_routes add constraint event_routes_distance_km_check CHECK (((distance_km IS NULL) OR (distance_km >= (0)::numeric)));
alter table public.event_routes add constraint event_routes_estimated_minutes_check CHECK (((estimated_minutes IS NULL) OR (estimated_minutes >= 0)));
alter table public.event_routes add constraint event_routes_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE;
alter table public.event_routes add constraint event_routes_event_id_name_key UNIQUE (event_id, name);
alter table public.event_shift_members add column if not exists shift_id uuid;
alter table public.event_shift_members alter column shift_id drop default;
alter table public.event_shift_members alter column shift_id set not null;
alter table public.event_shift_members add column if not exists status text default 'assigned'::text;
alter table public.event_shift_members alter column status set default 'assigned'::text;
alter table public.event_shift_members alter column status set not null;
alter table public.event_shift_members add column if not exists checked_in_at timestamp with time zone;
alter table public.event_shift_members alter column checked_in_at drop default;
alter table public.event_shift_members alter column checked_in_at drop not null;
alter table public.event_shift_members add column if not exists checked_out_at timestamp with time zone;
alter table public.event_shift_members alter column checked_out_at drop default;
alter table public.event_shift_members alter column checked_out_at drop not null;
alter table public.event_shift_members add column if not exists notes text;
alter table public.event_shift_members alter column notes drop default;
alter table public.event_shift_members alter column notes drop not null;
alter table public.event_shift_members add constraint event_shift_members_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE;
alter table public.event_shift_members add constraint event_shift_members_member_id_fkey FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE;
alter table public.event_shift_members add constraint event_shift_members_shift_id_fkey FOREIGN KEY (shift_id) REFERENCES event_shifts(id) ON DELETE CASCADE;
alter table public.event_shift_members add constraint event_shift_members_shift_id_member_id_key UNIQUE (shift_id, member_id);
alter table public.event_shift_members add constraint event_shift_members_status_check CHECK ((status = ANY (ARRAY['assigned'::text, 'confirmed'::text, 'present'::text, 'absent'::text, 'cancelled'::text])));
alter table public.event_shifts add column if not exists event_id uuid;
alter table public.event_shifts alter column event_id drop default;
alter table public.event_shifts alter column event_id set not null;
alter table public.event_shifts add column if not exists name text;
alter table public.event_shifts alter column name drop default;
alter table public.event_shifts alter column name set not null;
alter table public.event_shifts add column if not exists starts_at timestamp with time zone;
alter table public.event_shifts alter column starts_at drop default;
alter table public.event_shifts alter column starts_at set not null;
alter table public.event_shifts add column if not exists ends_at timestamp with time zone;
alter table public.event_shifts alter column ends_at drop default;
alter table public.event_shifts alter column ends_at set not null;
alter table public.event_shifts add column if not exists required_people integer default 1;
alter table public.event_shifts alter column required_people set default 1;
alter table public.event_shifts alter column required_people set not null;
alter table public.event_shifts add column if not exists status text default 'planned'::text;
alter table public.event_shifts alter column status set default 'planned'::text;
alter table public.event_shifts alter column status set not null;
alter table public.event_shifts add column if not exists notes text;
alter table public.event_shifts alter column notes drop default;
alter table public.event_shifts alter column notes drop not null;
alter table public.event_shifts add column if not exists created_at timestamp with time zone default now();
alter table public.event_shifts alter column created_at set default now();
alter table public.event_shifts alter column created_at set not null;
alter table public.event_shifts add column if not exists updated_at timestamp with time zone default now();
alter table public.event_shifts alter column updated_at set default now();
alter table public.event_shifts alter column updated_at set not null;
alter table public.event_shifts add constraint event_shifts_dates_check CHECK ((ends_at >= starts_at));
alter table public.event_shifts add constraint event_shifts_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE;
alter table public.event_shifts add constraint event_shifts_required_people_check CHECK ((required_people > 0));
alter table public.event_shifts add constraint event_shifts_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'active'::text, 'completed'::text, 'cancelled'::text])));
alter table public.event_task_assignees add column if not exists task_id uuid;
alter table public.event_task_assignees alter column task_id drop default;
alter table public.event_task_assignees alter column task_id set not null;
alter table public.event_task_assignees add column if not exists assigned_at timestamp with time zone default now();
alter table public.event_task_assignees alter column assigned_at set default now();
alter table public.event_task_assignees alter column assigned_at set not null;
alter table public.event_task_assignees add column if not exists acknowledged_at timestamp with time zone;
alter table public.event_task_assignees alter column acknowledged_at drop default;
alter table public.event_task_assignees alter column acknowledged_at drop not null;
alter table public.event_task_assignees add column if not exists completed_at timestamp with time zone;
alter table public.event_task_assignees alter column completed_at drop default;
alter table public.event_task_assignees alter column completed_at drop not null;
alter table public.event_task_assignees add column if not exists notes text;
alter table public.event_task_assignees alter column notes drop default;
alter table public.event_task_assignees alter column notes drop not null;
alter table public.event_task_assignees add constraint event_task_assignees_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE;
alter table public.event_task_assignees add constraint event_task_assignees_member_id_fkey FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE;
alter table public.event_task_assignees add constraint event_task_assignees_task_id_fkey FOREIGN KEY (task_id) REFERENCES event_tasks(id) ON DELETE CASCADE;
alter table public.event_task_assignees add constraint event_task_assignees_task_id_member_id_key UNIQUE (task_id, member_id);
alter table public.event_tasks add column if not exists event_id uuid;
alter table public.event_tasks alter column event_id drop default;
alter table public.event_tasks alter column event_id set not null;
alter table public.event_tasks add column if not exists priority text default 'normal'::text;
alter table public.event_tasks alter column priority set default 'normal'::text;
alter table public.event_tasks alter column priority set not null;
alter table public.event_tasks add column if not exists status text default 'pending'::text;
alter table public.event_tasks alter column status set default 'pending'::text;
alter table public.event_tasks alter column status set not null;
alter table public.event_tasks add column if not exists completed_at timestamp with time zone;
alter table public.event_tasks alter column completed_at drop default;
alter table public.event_tasks alter column completed_at drop not null;
alter table public.event_tasks add column if not exists notes text;
alter table public.event_tasks alter column notes drop default;
alter table public.event_tasks alter column notes drop not null;
alter table public.event_tasks add column if not exists created_at timestamp with time zone default now();
alter table public.event_tasks alter column created_at set default now();
alter table public.event_tasks alter column created_at set not null;
alter table public.event_tasks add column if not exists updated_at timestamp with time zone default now();
alter table public.event_tasks alter column updated_at set default now();
alter table public.event_tasks alter column updated_at set not null;
alter table public.event_tasks add constraint event_tasks_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE;
alter table public.event_tasks add constraint event_tasks_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'critical'::text])));
alter table public.event_tasks add constraint event_tasks_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'done'::text, 'cancelled'::text])));
alter table public.maintenance_attachments add column if not exists storage_path text;
alter table public.maintenance_attachments alter column storage_path drop default;
alter table public.maintenance_attachments alter column storage_path set not null;
alter table public.maintenance_attachments add column if not exists original_file_name text;
alter table public.maintenance_attachments alter column original_file_name drop default;
alter table public.maintenance_attachments alter column original_file_name set not null;
alter table public.maintenance_attachments add column if not exists mime_type text;
alter table public.maintenance_attachments alter column mime_type drop default;
alter table public.maintenance_attachments alter column mime_type drop not null;
alter table public.maintenance_attachments add column if not exists file_size bigint default 0;
alter table public.maintenance_attachments alter column file_size set default 0;
alter table public.maintenance_attachments alter column file_size set not null;
alter table public.maintenance_attachments add column if not exists created_at timestamp with time zone default now();
alter table public.maintenance_attachments alter column created_at set default now();
alter table public.maintenance_attachments alter column created_at set not null;
alter table public.maintenance_attachments add column if not exists updated_at timestamp with time zone default now();
alter table public.maintenance_attachments alter column updated_at set default now();
alter table public.maintenance_attachments alter column updated_at set not null;
alter table public.maintenance_attachments add constraint maintenance_attachments_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.maintenance_attachments add constraint maintenance_attachments_maintenance_id_fkey FOREIGN KEY (maintenance_id) REFERENCES maintenance_records(id) ON DELETE CASCADE;
alter table public.maintenance_attachments add constraint maintenance_attachments_member_id_fkey FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE;
alter table public.maintenance_attachments add constraint maintenance_attachments_size_nonnegative CHECK ((file_size >= 0));
alter table public.maintenance_attachments add constraint maintenance_attachments_storage_path_key UNIQUE (storage_path);
alter table public.maintenance_records add column if not exists motorcycle_id uuid;
alter table public.maintenance_records alter column motorcycle_id drop default;
alter table public.maintenance_records alter column motorcycle_id set not null;
alter table public.maintenance_records add column if not exists service_date date default CURRENT_DATE;
alter table public.maintenance_records alter column service_date set default CURRENT_DATE;
alter table public.maintenance_records alter column service_date set not null;
alter table public.maintenance_records add column if not exists service_type text;
alter table public.maintenance_records alter column service_type drop default;
alter table public.maintenance_records alter column service_type set not null;
alter table public.maintenance_records add column if not exists odometer_km integer;
alter table public.maintenance_records alter column odometer_km drop default;
alter table public.maintenance_records alter column odometer_km drop not null;
alter table public.maintenance_records add column if not exists workshop text;
alter table public.maintenance_records alter column workshop drop default;
alter table public.maintenance_records alter column workshop drop not null;
alter table public.maintenance_records add column if not exists cost numeric(12,2) default 0;
alter table public.maintenance_records alter column cost set default 0;
alter table public.maintenance_records alter column cost set not null;
alter table public.maintenance_records add column if not exists next_service_km integer;
alter table public.maintenance_records alter column next_service_km drop default;
alter table public.maintenance_records alter column next_service_km drop not null;
alter table public.maintenance_records add column if not exists created_at timestamp with time zone default now();
alter table public.maintenance_records alter column created_at set default now();
alter table public.maintenance_records alter column created_at set not null;
alter table public.maintenance_records add column if not exists updated_at timestamp with time zone default now();
alter table public.maintenance_records alter column updated_at set default now();
alter table public.maintenance_records alter column updated_at set not null;
alter table public.maintenance_records add constraint maintenance_records_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.maintenance_records add constraint maintenance_records_cost_nonnegative CHECK ((cost >= (0)::numeric));
alter table public.maintenance_records add constraint maintenance_records_member_id_fkey FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE;
alter table public.maintenance_records add constraint maintenance_records_motorcycle_id_fkey FOREIGN KEY (motorcycle_id) REFERENCES member_motorcycles(id) ON DELETE CASCADE;
alter table public.maintenance_records add constraint maintenance_records_next_km_nonnegative CHECK (((next_service_km IS NULL) OR (next_service_km >= 0)));
alter table public.maintenance_records add constraint maintenance_records_odometer_nonnegative CHECK (((odometer_km IS NULL) OR (odometer_km >= 0)));
alter table public.member_patch_awards add column if not exists member_id uuid;
alter table public.member_patch_awards alter column member_id drop default;
alter table public.member_patch_awards alter column member_id set not null;
alter table public.member_patch_awards add column if not exists patch_name text;
alter table public.member_patch_awards alter column patch_name drop default;
alter table public.member_patch_awards alter column patch_name set not null;
alter table public.member_patch_awards add column if not exists variant_name text;
alter table public.member_patch_awards alter column variant_name drop default;
alter table public.member_patch_awards alter column variant_name drop not null;
alter table public.member_patch_awards add column if not exists approved_at timestamp with time zone;
alter table public.member_patch_awards alter column approved_at drop default;
alter table public.member_patch_awards alter column approved_at drop not null;
alter table public.member_patch_awards add column if not exists delivered_at timestamp with time zone;
alter table public.member_patch_awards alter column delivered_at drop default;
alter table public.member_patch_awards alter column delivered_at drop not null;
alter table public.member_patch_awards add column if not exists delivery_location_name text;
alter table public.member_patch_awards alter column delivery_location_name drop default;
alter table public.member_patch_awards alter column delivery_location_name drop not null;
alter table public.member_patch_awards add column if not exists created_at timestamp with time zone default now();
alter table public.member_patch_awards alter column created_at set default now();
alter table public.member_patch_awards alter column created_at set not null;
alter table public.member_patch_awards add column if not exists updated_at timestamp with time zone default now();
alter table public.member_patch_awards alter column updated_at set default now();
alter table public.member_patch_awards alter column updated_at set not null;
alter table public.member_patch_awards add constraint member_patch_awards_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.member_patch_awards add constraint member_patch_awards_inventory_location_id_fkey FOREIGN KEY (inventory_location_id) REFERENCES inventory_locations(id) ON DELETE SET NULL;
alter table public.member_patch_awards add constraint member_patch_awards_member_id_fkey FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE;
alter table public.member_patch_awards add constraint member_patch_awards_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT;
alter table public.member_patch_awards add constraint member_patch_awards_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'delivered'::text, 'cancelled'::text])));
alter table public.member_patch_awards add constraint member_patch_awards_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE RESTRICT;
alter table public.member_status_history add column if not exists member_id uuid;
alter table public.member_status_history alter column member_id drop default;
alter table public.member_status_history alter column member_id set not null;
alter table public.member_status_history add column if not exists changed_by uuid default auth.uid();
alter table public.member_status_history alter column changed_by set default auth.uid();
alter table public.member_status_history alter column changed_by drop not null;
alter table public.member_status_history add column if not exists notes text;
alter table public.member_status_history alter column notes drop default;
alter table public.member_status_history alter column notes drop not null;
alter table public.member_status_history add constraint member_status_history_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.member_status_history add constraint member_status_history_member_id_fkey FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE;
alter table public.member_timeline add column if not exists member_id uuid;
alter table public.member_timeline alter column member_id drop default;
alter table public.member_timeline alter column member_id set not null;
alter table public.member_timeline add column if not exists event_type text;
alter table public.member_timeline alter column event_type drop default;
alter table public.member_timeline alter column event_type set not null;
alter table public.member_timeline add column if not exists event_date date default CURRENT_DATE;
alter table public.member_timeline alter column event_date type date using event_date::date;
alter table public.member_timeline alter column event_date set default CURRENT_DATE;
alter table public.member_timeline alter column event_date set not null;
alter table public.member_timeline add column if not exists visibility text default 'club'::text;
alter table public.member_timeline alter column visibility set default 'club'::text;
alter table public.member_timeline alter column visibility set not null;
alter table public.member_timeline add column if not exists created_at timestamp with time zone default now();
alter table public.member_timeline alter column created_at set default now();
alter table public.member_timeline alter column created_at set not null;
alter table public.member_timeline add constraint member_timeline_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.member_timeline add constraint member_timeline_member_id_fkey FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE;
alter table public.member_timeline add constraint member_timeline_visibility_check CHECK ((visibility = ANY (ARRAY['club'::text, 'member_private'::text, 'direction'::text])));
alter table public.stock_lots add column if not exists quantity numeric(12,2);
alter table public.stock_lots alter column quantity type numeric(12,2) using quantity::numeric(12,2);
alter table public.stock_lots alter column quantity drop default;
alter table public.stock_lots alter column quantity set not null;
alter table public.stock_lots add column if not exists unit_cost numeric(12,2);
alter table public.stock_lots alter column unit_cost type numeric(12,2) using unit_cost::numeric(12,2);
alter table public.stock_lots alter column unit_cost drop default;
alter table public.stock_lots alter column unit_cost drop not null;
alter table public.stock_lots add column if not exists created_at timestamp with time zone default now();
alter table public.stock_lots alter column created_at set default now();
alter table public.stock_lots alter column created_at set not null;
alter table public.stock_lots add column if not exists updated_at timestamp with time zone default now();
alter table public.stock_lots alter column updated_at set default now();
alter table public.stock_lots alter column updated_at set not null;
alter table public.stock_reservations add column if not exists quantity numeric(12,2);
alter table public.stock_reservations alter column quantity type numeric(12,2) using quantity::numeric(12,2);
alter table public.stock_reservations alter column quantity drop default;
alter table public.stock_reservations alter column quantity set not null;
alter table public.stock_reservations add column if not exists created_at timestamp with time zone default now();
alter table public.stock_reservations alter column created_at set default now();
alter table public.stock_reservations alter column created_at set not null;
alter table public.stock_reservations add column if not exists updated_at timestamp with time zone default now();
alter table public.stock_reservations alter column updated_at set default now();
alter table public.stock_reservations alter column updated_at set not null;
alter table public.activity_feed add column if not exists activity_type text;
alter table public.activity_feed alter column activity_type drop default;
alter table public.activity_feed alter column activity_type set not null;
alter table public.activity_feed add constraint activity_feed_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public.activity_feed add constraint activity_feed_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.audit_log add column if not exists club_id uuid;
alter table public.audit_log alter column club_id drop default;
alter table public.audit_log alter column club_id drop not null;
alter table public.audit_log add column if not exists entity_type text;
alter table public.audit_log alter column entity_type drop default;
alter table public.audit_log alter column entity_type set not null;
alter table public.audit_log add column if not exists action text;
alter table public.audit_log alter column action drop default;
alter table public.audit_log alter column action set not null;
alter table public.audit_log add constraint audit_log_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id);
alter table public.audit_log add constraint audit_log_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.club_positions add column if not exists code text;
alter table public.club_positions alter column code drop default;
alter table public.club_positions alter column code set not null;
alter table public.club_positions add column if not exists sort_order integer default 0;
alter table public.club_positions alter column sort_order set default 0;
alter table public.club_positions alter column sort_order set not null;
alter table public.club_positions add column if not exists active boolean default true;
alter table public.club_positions alter column active set default true;
alter table public.club_positions alter column active set not null;
alter table public.club_positions add constraint club_positions_club_id_code_key UNIQUE (club_id, code);
alter table public.club_positions add constraint club_positions_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.clubs add column if not exists primary_color text default '#0C18D2'::text;
alter table public.clubs alter column primary_color set default '#0C18D2'::text;
alter table public.clubs alter column primary_color set not null;
alter table public.clubs add column if not exists currency text default 'EUR'::text;
alter table public.clubs alter column currency set default 'EUR'::text;
alter table public.clubs alter column currency set not null;
alter table public.clubs add column if not exists timezone text default 'Europe/Lisbon'::text;
alter table public.clubs alter column timezone set default 'Europe/Lisbon'::text;
alter table public.clubs alter column timezone set not null;
alter table public.clubs add column if not exists active boolean default true;
alter table public.clubs alter column active set default true;
alter table public.clubs alter column active set not null;
alter table public.clubs add column if not exists updated_at timestamp with time zone default now();
alter table public.clubs alter column updated_at set default now();
alter table public.clubs alter column updated_at set not null;
CREATE TRIGGER clubs_set_updated_at BEFORE UPDATE ON public.clubs FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
alter table public.cost_centers add column if not exists active boolean default true;
alter table public.cost_centers alter column active set default true;
alter table public.cost_centers alter column active set not null;
alter table public.cost_centers add constraint cost_centers_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.cost_centers add constraint cost_centers_club_id_name_key UNIQUE (club_id, name);
alter table public.documents add column if not exists sensitive boolean default false;
alter table public.documents alter column sensitive set default false;
alter table public.documents alter column sensitive set not null;
alter table public.documents add column if not exists linked_entity_type text;
alter table public.documents alter column linked_entity_type drop default;
alter table public.documents alter column linked_entity_type drop not null;
alter table public.documents add column if not exists linked_entity_id uuid;
alter table public.documents alter column linked_entity_id drop default;
alter table public.documents alter column linked_entity_id drop not null;
alter table public.documents add column if not exists created_at timestamp with time zone default now();
alter table public.documents alter column created_at set default now();
alter table public.documents alter column created_at set not null;
alter table public.documents add column if not exists status text default 'active'::text;
alter table public.documents alter column status set default 'active'::text;
alter table public.documents alter column status set not null;
alter table public.documents add column if not exists tags text;
alter table public.documents alter column tags drop default;
alter table public.documents alter column tags drop not null;
alter table public.documents add constraint documents_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.documents add constraint documents_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
alter table public.documents add constraint documents_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE SET NULL;
alter table public.documents add constraint documents_owner_profile_id_fkey FOREIGN KEY (owner_profile_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public.events add column if not exists status event_status default 'draft'::event_status;
alter table public.events alter column status drop default;
alter table public.events alter column status type event_status using status::event_status;
alter table public.events alter column status set default 'draft'::event_status;
alter table public.events alter column status set not null;
alter table public.events add column if not exists created_at timestamp with time zone default now();
alter table public.events alter column created_at set default now();
alter table public.events alter column created_at set not null;
alter table public.events add column if not exists updated_at timestamp with time zone default now();
alter table public.events alter column updated_at set default now();
alter table public.events alter column updated_at set not null;
alter table public.events add constraint events_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
CREATE TRIGGER events_set_updated_at BEFORE UPDATE ON public.events FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
alter table public.fee_obligations add column if not exists amount numeric(12,2);
alter table public.fee_obligations alter column amount drop default;
alter table public.fee_obligations alter column amount set not null;
alter table public.fee_obligations add column if not exists paid_amount numeric(12,2) default 0;
alter table public.fee_obligations alter column paid_amount set default 0;
alter table public.fee_obligations alter column paid_amount set not null;
alter table public.fee_obligations add column if not exists status fee_status default 'pending'::fee_status;
alter table public.fee_obligations alter column status drop default;
alter table public.fee_obligations alter column status type fee_status using status::fee_status;
alter table public.fee_obligations alter column status set default 'pending'::fee_status;
alter table public.fee_obligations alter column status set not null;
alter table public.fee_obligations add column if not exists created_at timestamp with time zone default now();
alter table public.fee_obligations alter column created_at set default now();
alter table public.fee_obligations alter column created_at set not null;
alter table public.fee_payment_allocations add column if not exists amount numeric(12,2);
alter table public.fee_payment_allocations alter column amount drop default;
alter table public.fee_payment_allocations alter column amount set not null;
alter table public.fee_payment_allocations add column if not exists created_at timestamp with time zone default now();
alter table public.fee_payment_allocations alter column created_at set default now();
alter table public.fee_payment_allocations alter column created_at set not null;
alter table public.fee_payment_allocations add column if not exists updated_at timestamp with time zone default now();
alter table public.fee_payment_allocations alter column updated_at set default now();
alter table public.fee_payment_allocations alter column updated_at set not null;
alter table public.fee_payments add column if not exists transaction_id uuid;
alter table public.fee_payments alter column transaction_id drop default;
alter table public.fee_payments alter column transaction_id set not null;
alter table public.fee_payments add column if not exists amount numeric(12,2);
alter table public.fee_payments alter column amount drop default;
alter table public.fee_payments alter column amount set not null;
alter table public.fee_payments add column if not exists status text default 'confirmed'::text;
alter table public.fee_payments alter column status set default 'confirmed'::text;
alter table public.fee_payments alter column status set not null;
alter table public.fee_plans add column if not exists amount numeric(12,2);
alter table public.fee_plans alter column amount drop default;
alter table public.fee_plans alter column amount set not null;
alter table public.fee_plans add column if not exists frequency text;
alter table public.fee_plans alter column frequency drop default;
alter table public.fee_plans alter column frequency set not null;
alter table public.fee_plans add column if not exists active boolean default true;
alter table public.fee_plans alter column active set default true;
alter table public.fee_plans alter column active set not null;
alter table public.fee_plans add column if not exists created_at timestamp with time zone default now();
alter table public.fee_plans alter column created_at set default now();
alter table public.fee_plans alter column created_at set not null;
alter table public.fee_plans add constraint fee_plans_amount_check CHECK ((amount >= (0)::numeric));
alter table public.fee_plans add constraint fee_plans_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.fee_plans add constraint fee_plans_frequency_check CHECK ((frequency = ANY (ARRAY['monthly'::text, 'quarterly'::text, 'annual'::text, 'custom'::text])));
alter table public.member_positions add column if not exists member_id uuid;
alter table public.member_positions alter column member_id drop default;
alter table public.member_positions alter column member_id set not null;
alter table public.member_positions add column if not exists position_id uuid;
alter table public.member_positions alter column position_id drop default;
alter table public.member_positions alter column position_id set not null;
alter table public.member_positions add column if not exists is_primary boolean default false;
alter table public.member_positions alter column is_primary set default false;
alter table public.member_positions alter column is_primary set not null;
alter table public.member_positions add column if not exists created_at timestamp with time zone default now();
alter table public.member_positions alter column created_at set default now();
alter table public.member_positions alter column created_at set not null;
alter table public.member_positions add constraint member_positions_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.member_positions add constraint member_positions_member_id_position_id_starts_at_key UNIQUE (member_id, position_id, starts_at);
alter table public.members add column if not exists status member_status default 'active'::member_status;
alter table public.members alter column status drop default;
alter table public.members alter column status type member_status using status::member_status;
alter table public.members alter column status set default 'active'::member_status;
alter table public.members alter column status set not null;
alter table public.members add column if not exists photo_path text;
alter table public.members alter column photo_path drop default;
alter table public.members alter column photo_path drop not null;
alter table public.members add column if not exists updated_at timestamp with time zone default now();
alter table public.members alter column updated_at set default now();
alter table public.members alter column updated_at set not null;
alter table public.members add column if not exists motorcycle text;
alter table public.members alter column motorcycle drop default;
alter table public.members alter column motorcycle drop not null;
alter table public.members add column if not exists registration text;
alter table public.members alter column registration drop default;
alter table public.members alter column registration drop not null;
alter table public.members add constraint members_club_id_member_number_key UNIQUE (club_id, member_number);
CREATE TRIGGER members_set_updated_at BEFORE UPDATE ON public.members FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
alter table public.notifications add constraint notifications_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.product_variants add column if not exists product_id uuid;
alter table public.product_variants alter column product_id drop default;
alter table public.product_variants alter column product_id set not null;
alter table public.product_variants add column if not exists active boolean default true;
alter table public.product_variants alter column active set default true;
alter table public.product_variants alter column active set not null;
alter table public.product_variants add column if not exists minimum_stock numeric(12,2) default 0;
alter table public.product_variants alter column minimum_stock set default 0;
alter table public.product_variants alter column minimum_stock set not null;
alter table public.product_variants add column if not exists cost numeric(12,2);
alter table public.product_variants alter column cost drop default;
alter table public.product_variants alter column cost drop not null;
alter table public.product_variants add column if not exists sale_price numeric(12,2);
alter table public.product_variants alter column sale_price drop default;
alter table public.product_variants alter column sale_price drop not null;
alter table public.products add column if not exists active boolean default true;
alter table public.products alter column active set default true;
alter table public.products alter column active set not null;
alter table public.products add column if not exists created_at timestamp with time zone default now();
alter table public.products alter column created_at set default now();
alter table public.products alter column created_at set not null;
alter table public.products add constraint products_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.profiles add column if not exists id uuid;
alter table public.profiles alter column id drop default;
alter table public.profiles alter column id set not null;
alter table public.profiles add column if not exists active boolean default true;
alter table public.profiles alter column active set default true;
alter table public.profiles alter column active set not null;
alter table public.profiles add column if not exists updated_at timestamp with time zone default now();
alter table public.profiles alter column updated_at set default now();
alter table public.profiles alter column updated_at set not null;
CREATE TRIGGER profiles_set_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
alter table public.stock_movements add column if not exists quantity numeric(12,2);
alter table public.stock_movements alter column quantity drop default;
alter table public.stock_movements alter column quantity set not null;
alter table public.stock_movements add column if not exists unit_cost numeric(12,2);
alter table public.stock_movements alter column unit_cost drop default;
alter table public.stock_movements alter column unit_cost drop not null;
alter table public.stock_movements add column if not exists created_at timestamp with time zone default now();
alter table public.stock_movements alter column created_at set default now();
alter table public.stock_movements alter column created_at set not null;
alter table public.maintenance_records drop constraint fk_maintenance_records_motorcycle_id;
commit;
