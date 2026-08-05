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
  email citext,
  phone text,
  avatar_path text,
  locale text,
  active boolean default true,
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz default now()
);

alter table public.profiles add column if not exists full_name text;

alter table public.profiles add column if not exists email citext;

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
  profile_id uuid,
  member_id uuid,
  active boolean default true,
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
create table if not exists public.user_permission_overrides (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  profile_id uuid,
  permission_id uuid,
  allowed boolean,
  scope_type text,
  scope_id uuid,
  valid_from timestamptz,
  valid_until timestamptz,
  reason text,
  granted_by uuid
);

alter table public.user_permission_overrides add column if not exists club_id uuid;

alter table public.user_permission_overrides add column if not exists profile_id uuid;

alter table public.user_permission_overrides add column if not exists permission_id uuid;

alter table public.user_permission_overrides add column if not exists allowed boolean;

alter table public.user_permission_overrides add column if not exists scope_type text;

alter table public.user_permission_overrides add column if not exists scope_id uuid;

alter table public.user_permission_overrides add column if not exists valid_from timestamptz;

alter table public.user_permission_overrides add column if not exists valid_until timestamptz;

alter table public.user_permission_overrides add column if not exists reason text;

alter table public.user_permission_overrides add column if not exists granted_by uuid;

create index if not exists idx_user_permission_overrides_club_id on public.user_permission_overrides(club_id);

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
  email citext,
  phone text,
  address jsonb,
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

alter table public.members add column if not exists email citext;

alter table public.members add column if not exists phone text;

alter table public.members add column if not exists address jsonb;

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
create table if not exists public.payables (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  supplier_id uuid,
  event_id uuid,
  invoice_number text,
  document_date date,
  due_date date,
  total_amount numeric(14,2),
  paid_amount numeric(14,2) default 0,
  status text,
  document_id uuid
);

alter table public.payables add column if not exists club_id uuid;

alter table public.payables add column if not exists supplier_id uuid;

alter table public.payables add column if not exists event_id uuid;

alter table public.payables add column if not exists invoice_number text;

alter table public.payables add column if not exists document_date date;

alter table public.payables add column if not exists due_date date;

alter table public.payables add column if not exists total_amount numeric(14,2);

alter table public.payables add column if not exists paid_amount numeric(14,2) default 0;

alter table public.payables add column if not exists status text;

alter table public.payables add column if not exists document_id uuid;

create index if not exists idx_payables_club_id on public.payables(club_id);

-- Tesouraria: Contas a receber.
create table if not exists public.receivables (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  party_type text,
  party_id uuid,
  description text,
  due_date date,
  total_amount numeric(14,2),
  received_amount numeric(14,2),
  status text
);

alter table public.receivables add column if not exists club_id uuid;

alter table public.receivables add column if not exists party_type text;

alter table public.receivables add column if not exists party_id uuid;

alter table public.receivables add column if not exists description text;

alter table public.receivables add column if not exists due_date date;

alter table public.receivables add column if not exists total_amount numeric(14,2);

alter table public.receivables add column if not exists received_amount numeric(14,2);

alter table public.receivables add column if not exists status text;

create index if not exists idx_receivables_club_id on public.receivables(club_id);

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
create table if not exists public.cash_sessions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  account_id uuid,
  event_id uuid,
  opened_by uuid,
  opened_at timestamptz,
  opening_amount numeric(14,2),
  closed_by uuid,
  closed_at timestamptz,
  expected_amount numeric(14,2),
  counted_amount numeric(14,2),
  difference numeric(14,2),
  status text
);

alter table public.cash_sessions add column if not exists club_id uuid;

alter table public.cash_sessions add column if not exists account_id uuid;

alter table public.cash_sessions add column if not exists event_id uuid;

alter table public.cash_sessions add column if not exists opened_by uuid;

alter table public.cash_sessions add column if not exists opened_at timestamptz;

alter table public.cash_sessions add column if not exists opening_amount numeric(14,2);

alter table public.cash_sessions add column if not exists closed_by uuid;

alter table public.cash_sessions add column if not exists closed_at timestamptz;

alter table public.cash_sessions add column if not exists expected_amount numeric(14,2);

alter table public.cash_sessions add column if not exists counted_amount numeric(14,2);

alter table public.cash_sessions add column if not exists difference numeric(14,2);

alter table public.cash_sessions add column if not exists status text;

create index if not exists idx_cash_sessions_club_id on public.cash_sessions(club_id);

-- Tesouraria: Reconciliação por período.
create table if not exists public.bank_reconciliations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  account_id uuid,
  period_start date,
  period_end date,
  statement_balance numeric(14,2),
  system_balance numeric(14,2),
  difference numeric(14,2),
  status text,
  document_id uuid
);

alter table public.bank_reconciliations add column if not exists club_id uuid;

alter table public.bank_reconciliations add column if not exists account_id uuid;

alter table public.bank_reconciliations add column if not exists period_start date;

alter table public.bank_reconciliations add column if not exists period_end date;

alter table public.bank_reconciliations add column if not exists statement_balance numeric(14,2);

alter table public.bank_reconciliations add column if not exists system_balance numeric(14,2);

alter table public.bank_reconciliations add column if not exists difference numeric(14,2);

alter table public.bank_reconciliations add column if not exists status text;

alter table public.bank_reconciliations add column if not exists document_id uuid;

create index if not exists idx_bank_reconciliations_club_id on public.bank_reconciliations(club_id);

-- Tesouraria: Orçamentos.
create table if not exists public.budgets (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  name text not null,
  scope_type text,
  scope_id uuid,
  period_start date,
  period_end date,
  status text
);

alter table public.budgets add column if not exists club_id uuid;

alter table public.budgets add column if not exists name text;

alter table public.budgets add column if not exists scope_type text;

alter table public.budgets add column if not exists scope_id uuid;

alter table public.budgets add column if not exists period_start date;

alter table public.budgets add column if not exists period_end date;

alter table public.budgets add column if not exists status text;

create index if not exists idx_budgets_club_id on public.budgets(club_id);

-- Tesouraria: Linhas de orçamento.
create table if not exists public.budget_lines (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  budget_id uuid,
  category_id uuid,
  cost_center_id uuid,
  planned_amount numeric(14,2),
  committed_amount numeric(14,2),
  actual_amount numeric(14,2)
);

alter table public.budget_lines add column if not exists club_id uuid;

alter table public.budget_lines add column if not exists budget_id uuid;

alter table public.budget_lines add column if not exists category_id uuid;

alter table public.budget_lines add column if not exists cost_center_id uuid;

alter table public.budget_lines add column if not exists planned_amount numeric(14,2);

alter table public.budget_lines add column if not exists committed_amount numeric(14,2);

alter table public.budget_lines add column if not exists actual_amount numeric(14,2);

create index if not exists idx_budget_lines_club_id on public.budget_lines(club_id);

-- Quotas: Planos configuráveis.
create table if not exists public.fee_plans (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  name text not null,
  frequency text,
  amount numeric(14,2),
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
  amount numeric(14,2),
  paid_amount numeric(14,2) default 0,
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
  amount numeric(14,2),
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
  amount numeric(14,2)
);

alter table public.fee_payment_allocations add column if not exists club_id uuid;

alter table public.fee_payment_allocations add column if not exists fee_payment_id uuid;

alter table public.fee_payment_allocations add column if not exists fee_obligation_id uuid;

alter table public.fee_payment_allocations add column if not exists amount numeric(14,2);

create index if not exists idx_fee_payment_allocations_club_id on public.fee_payment_allocations(club_id);

-- Quotas: Crédito do membro.
create table if not exists public.fee_credits (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  origin_payment_id uuid,
  amount numeric(14,2),
  remaining_amount numeric(14,2),
  status text,
  created_at timestamptz not null default now()
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
create table if not exists public.fee_exemptions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  starts_at date,
  ends_at date,
  type text,
  value numeric(14,2),
  reason text,
  approved_by uuid
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
create table if not exists public.fee_adjustments (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  obligation_id uuid,
  adjustment_type text,
  amount numeric(14,2),
  reason text,
  approved_by uuid,
  created_at timestamptz not null default now()
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
create table if not exists public.reported_payments (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  member_id uuid,
  amount numeric(14,2),
  payment_date date,
  method_id uuid,
  reference text,
  intended_periods jsonb,
  status text,
  attachment_id uuid,
  validated_by uuid,
  validation_notes text
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
  location jsonb,
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

alter table public.events add column if not exists location jsonb;

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
create table if not exists public.event_bands (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid,
  name text not null,
  contact jsonb,
  fee numeric(14,2),
  schedule jsonb,
  technical_rider_document_id uuid,
  contract_document_id uuid,
  payment_status text,
  status text
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
create table if not exists public.event_exhibitors (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid,
  supplier_id uuid,
  name text not null,
  category text,
  requirements jsonb,
  fee numeric(14,2),
  deposit numeric(14,2),
  location_code text,
  payment_status text,
  status text
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
create table if not exists public.event_sponsors (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid,
  name text not null,
  support_type text,
  monetary_value numeric(14,2),
  in_kind_description text,
  benefits text,
  logo_path text,
  status text
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
  cost numeric(14,2),
  sale_price numeric(14,2),
  minimum_stock numeric(14,2) default 0,
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
  quantity numeric(14,2),
  from_location_id uuid,
  to_location_id uuid,
  lot_id uuid,
  event_id uuid,
  member_id uuid,
  source_table text,
  source_id uuid,
  unit_cost numeric(14,2),
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
  tags text[]
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
  document_id uuid,
  version_number integer,
  attachment_id uuid,
  change_notes text,
  created_by uuid,
  created_at timestamptz not null default now()
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
  document_id uuid,
  entity_type text,
  entity_id uuid,
  link_role text
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
  id bigint generated always as identity primary key,
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
create table if not exists public.polls (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  title text not null,
  description text,
  anonymous boolean,
  multiple_choice boolean,
  starts_at timestamptz,
  ends_at timestamptz,
  status text
);

alter table public.polls add column if not exists club_id uuid;

alter table public.polls add column if not exists title text;

alter table public.polls add column if not exists description text;

alter table public.polls add column if not exists anonymous boolean;

alter table public.polls add column if not exists multiple_choice boolean;

alter table public.polls add column if not exists starts_at timestamptz;

alter table public.polls add column if not exists ends_at timestamptz;

alter table public.polls add column if not exists status text;

create index if not exists idx_polls_club_id on public.polls(club_id);

-- Documentos e comunicação: Opções.
create table if not exists public.poll_options (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  poll_id uuid,
  label text,
  sort_order integer
);

alter table public.poll_options add column if not exists club_id uuid;

alter table public.poll_options add column if not exists poll_id uuid;

alter table public.poll_options add column if not exists label text;

alter table public.poll_options add column if not exists sort_order integer;

create index if not exists idx_poll_options_club_id on public.poll_options(club_id);

-- Documentos e comunicação: Votos.
create table if not exists public.poll_votes (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  poll_id uuid,
  option_id uuid,
  profile_id uuid,
  created_at timestamptz not null default now()
);

alter table public.poll_votes add column if not exists club_id uuid;

alter table public.poll_votes add column if not exists poll_id uuid;

alter table public.poll_votes add column if not exists option_id uuid;

alter table public.poll_votes add column if not exists profile_id uuid;

alter table public.poll_votes add column if not exists created_at timestamptz default now();

create index if not exists idx_poll_votes_club_id on public.poll_votes(club_id);

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
create table if not exists public.imports (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  import_type text,
  original_attachment_id uuid,
  mapping jsonb,
  status text,
  created_by uuid,
  confirmed_by uuid,
  created_at timestamptz not null default now()
);

alter table public.imports add column if not exists club_id uuid;

alter table public.imports add column if not exists import_type text;

alter table public.imports add column if not exists original_attachment_id uuid;

alter table public.imports add column if not exists mapping jsonb;

alter table public.imports add column if not exists status text;

alter table public.imports add column if not exists created_by uuid;

alter table public.imports add column if not exists confirmed_by uuid;

alter table public.imports add column if not exists created_at timestamptz default now();

create index if not exists idx_imports_club_id on public.imports(club_id);

-- Plataforma e futuro: Pré-visualização/editável.
create table if not exists public.import_rows (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  import_id uuid,
  row_number integer,
  raw_data jsonb,
  normalized_data jsonb,
  errors jsonb,
  warnings jsonb,
  status text,
  created_entity_type text,
  created_entity_id uuid
);

alter table public.import_rows add column if not exists club_id uuid;

alter table public.import_rows add column if not exists import_id uuid;

alter table public.import_rows add column if not exists row_number integer;

alter table public.import_rows add column if not exists raw_data jsonb;

alter table public.import_rows add column if not exists normalized_data jsonb;

alter table public.import_rows add column if not exists errors jsonb;

alter table public.import_rows add column if not exists warnings jsonb;

alter table public.import_rows add column if not exists status text;

alter table public.import_rows add column if not exists created_entity_type text;

alter table public.import_rows add column if not exists created_entity_id uuid;

create index if not exists idx_import_rows_club_id on public.import_rows(club_id);

-- Plataforma e futuro: Exportações e pacotes integrais.
create table if not exists public.exports (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  export_type text,
  filters jsonb,
  format text,
  status text,
  attachment_id uuid,
  reason text,
  requested_by uuid,
  created_at timestamptz not null default now()
);

alter table public.exports add column if not exists club_id uuid;

alter table public.exports add column if not exists export_type text;

alter table public.exports add column if not exists filters jsonb;

alter table public.exports add column if not exists format text;

alter table public.exports add column if not exists status text;

alter table public.exports add column if not exists attachment_id uuid;

alter table public.exports add column if not exists reason text;

alter table public.exports add column if not exists requested_by uuid;

alter table public.exports add column if not exists created_at timestamptz default now();

create index if not exists idx_exports_club_id on public.exports(club_id);

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

do $$ begin
 alter table public.stock_movements add constraint fk_stock_movements_variant_id
 foreign key (variant_id) references public.product_variants(id) on delete cascade;
exception when duplicate_object then null; when undefined_column then null; end $$;

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

create or replace function public.has_permission(target_club uuid, permission_code text)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(
   select 1 from public.club_memberships cm
   join public.membership_roles mr on mr.membership_id=cm.id
   join public.role_permissions rp on rp.role_id=mr.role_id
   join public.permissions p on p.id=rp.permission_id
   where cm.club_id=target_club and cm.profile_id=auth.uid()
     and coalesce(cm.active,true) and p.code=permission_code
 ) or exists(
   select 1 from public.club_memberships cm
   join public.user_permission_overrides upo on upo.membership_id=cm.id
   join public.permissions p on p.id=upo.permission_id
   where cm.club_id=target_club and cm.profile_id=auth.uid()
     and upo.effect='allow' and p.code=permission_code
     and (upo.valid_until is null or upo.valid_until>=current_date)
 );
$$;

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

do $$ begin
   execute 'drop policy if exists club_memberships_tenant on public.club_memberships';
   execute 'create policy club_memberships_tenant on public.club_memberships for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

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
   execute 'create policy membership_roles_tenant on public.membership_roles for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.user_permission_overrides enable row level security;

do $$ begin
   execute 'drop policy if exists user_permission_overrides_tenant on public.user_permission_overrides';
   execute 'create policy user_permission_overrides_tenant on public.user_permission_overrides for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.permission_change_log enable row level security;

do $$ begin
   execute 'drop policy if exists permission_change_log_tenant on public.permission_change_log';
   execute 'create policy permission_change_log_tenant on public.permission_change_log for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.members enable row level security;

do $$ begin
   execute 'drop policy if exists members_tenant on public.members';
   execute 'create policy members_tenant on public.members for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.member_emergency_data enable row level security;

do $$ begin
   execute 'drop policy if exists member_emergency_data_tenant on public.member_emergency_data';
   execute 'create policy member_emergency_data_tenant on public.member_emergency_data for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.member_status_history enable row level security;

do $$ begin
   execute 'drop policy if exists member_status_history_tenant on public.member_status_history';
   execute 'create policy member_status_history_tenant on public.member_status_history for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.club_positions enable row level security;

do $$ begin
   execute 'drop policy if exists club_positions_tenant on public.club_positions';
   execute 'create policy club_positions_tenant on public.club_positions for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.member_positions enable row level security;

do $$ begin
   execute 'drop policy if exists member_positions_tenant on public.member_positions';
   execute 'create policy member_positions_tenant on public.member_positions for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.member_patch_awards enable row level security;

do $$ begin
   execute 'drop policy if exists member_patch_awards_tenant on public.member_patch_awards';
   execute 'create policy member_patch_awards_tenant on public.member_patch_awards for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.assigned_assets enable row level security;

do $$ begin
   execute 'drop policy if exists assigned_assets_tenant on public.assigned_assets';
   execute 'create policy assigned_assets_tenant on public.assigned_assets for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.member_timeline enable row level security;

do $$ begin
   execute 'drop policy if exists member_timeline_tenant on public.member_timeline';
   execute 'create policy member_timeline_tenant on public.member_timeline for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

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

do $$ begin
   execute 'drop policy if exists maintenance_records_tenant on public.maintenance_records';
   execute 'create policy maintenance_records_tenant on public.maintenance_records for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.maintenance_attachments enable row level security;

do $$ begin
   execute 'drop policy if exists maintenance_attachments_tenant on public.maintenance_attachments';
   execute 'create policy maintenance_attachments_tenant on public.maintenance_attachments for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

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

do $$ begin
   execute 'drop policy if exists cost_centers_tenant on public.cost_centers';
   execute 'create policy cost_centers_tenant on public.cost_centers for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

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

alter table public.payables enable row level security;

do $$ begin
   execute 'drop policy if exists payables_tenant on public.payables';
   execute 'create policy payables_tenant on public.payables for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.receivables enable row level security;

do $$ begin
   execute 'drop policy if exists receivables_tenant on public.receivables';
   execute 'create policy receivables_tenant on public.receivables for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.reimbursement_requests enable row level security;

do $$ begin
   execute 'drop policy if exists reimbursement_requests_tenant on public.reimbursement_requests';
   execute 'create policy reimbursement_requests_tenant on public.reimbursement_requests for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.cash_sessions enable row level security;

do $$ begin
   execute 'drop policy if exists cash_sessions_tenant on public.cash_sessions';
   execute 'create policy cash_sessions_tenant on public.cash_sessions for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.bank_reconciliations enable row level security;

do $$ begin
   execute 'drop policy if exists bank_reconciliations_tenant on public.bank_reconciliations';
   execute 'create policy bank_reconciliations_tenant on public.bank_reconciliations for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.budgets enable row level security;

do $$ begin
   execute 'drop policy if exists budgets_tenant on public.budgets';
   execute 'create policy budgets_tenant on public.budgets for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.budget_lines enable row level security;

do $$ begin
   execute 'drop policy if exists budget_lines_tenant on public.budget_lines';
   execute 'create policy budget_lines_tenant on public.budget_lines for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.fee_plans enable row level security;

do $$ begin
   execute 'drop policy if exists fee_plans_tenant on public.fee_plans';
   execute 'create policy fee_plans_tenant on public.fee_plans for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.member_fee_assignments enable row level security;

do $$ begin
   execute 'drop policy if exists member_fee_assignments_tenant on public.member_fee_assignments';
   execute 'create policy member_fee_assignments_tenant on public.member_fee_assignments for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.fee_obligations enable row level security;

do $$ begin
   execute 'drop policy if exists fee_obligations_tenant on public.fee_obligations';
   execute 'create policy fee_obligations_tenant on public.fee_obligations for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.fee_payments enable row level security;

do $$ begin
   execute 'drop policy if exists fee_payments_tenant on public.fee_payments';
   execute 'create policy fee_payments_tenant on public.fee_payments for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.fee_payment_allocations enable row level security;

do $$ begin
   execute 'drop policy if exists fee_payment_allocations_tenant on public.fee_payment_allocations';
   execute 'create policy fee_payment_allocations_tenant on public.fee_payment_allocations for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.fee_credits enable row level security;

do $$ begin
   execute 'drop policy if exists fee_credits_tenant on public.fee_credits';
   execute 'create policy fee_credits_tenant on public.fee_credits for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.fee_exemptions enable row level security;

do $$ begin
   execute 'drop policy if exists fee_exemptions_tenant on public.fee_exemptions';
   execute 'create policy fee_exemptions_tenant on public.fee_exemptions for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.fee_adjustments enable row level security;

do $$ begin
   execute 'drop policy if exists fee_adjustments_tenant on public.fee_adjustments';
   execute 'create policy fee_adjustments_tenant on public.fee_adjustments for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.fee_receipts enable row level security;

do $$ begin
   execute 'drop policy if exists fee_receipts_tenant on public.fee_receipts';
   execute 'create policy fee_receipts_tenant on public.fee_receipts for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.reported_payments enable row level security;

do $$ begin
   execute 'drop policy if exists reported_payments_tenant on public.reported_payments';
   execute 'create policy reported_payments_tenant on public.reported_payments for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

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

do $$ begin
   execute 'drop policy if exists events_tenant on public.events';
   execute 'create policy events_tenant on public.events for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_proposals enable row level security;

do $$ begin
   execute 'drop policy if exists event_proposals_tenant on public.event_proposals';
   execute 'create policy event_proposals_tenant on public.event_proposals for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_participants enable row level security;

do $$ begin
   execute 'drop policy if exists event_participants_tenant on public.event_participants';
   execute 'create policy event_participants_tenant on public.event_participants for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_guests enable row level security;

do $$ begin
   execute 'drop policy if exists event_guests_tenant on public.event_guests';
   execute 'create policy event_guests_tenant on public.event_guests for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_tasks enable row level security;

do $$ begin
   execute 'drop policy if exists event_tasks_tenant on public.event_tasks';
   execute 'create policy event_tasks_tenant on public.event_tasks for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_task_assignees enable row level security;

do $$ begin
   execute 'drop policy if exists event_task_assignees_tenant on public.event_task_assignees';
   execute 'create policy event_task_assignees_tenant on public.event_task_assignees for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_shifts enable row level security;

do $$ begin
   execute 'drop policy if exists event_shifts_tenant on public.event_shifts';
   execute 'create policy event_shifts_tenant on public.event_shifts for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_shift_members enable row level security;

do $$ begin
   execute 'drop policy if exists event_shift_members_tenant on public.event_shift_members';
   execute 'create policy event_shift_members_tenant on public.event_shift_members for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_program enable row level security;

do $$ begin
   execute 'drop policy if exists event_program_tenant on public.event_program';
   execute 'create policy event_program_tenant on public.event_program for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_routes enable row level security;

do $$ begin
   execute 'drop policy if exists event_routes_tenant on public.event_routes';
   execute 'create policy event_routes_tenant on public.event_routes for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_bands enable row level security;

do $$ begin
   execute 'drop policy if exists event_bands_tenant on public.event_bands';
   execute 'create policy event_bands_tenant on public.event_bands for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_exhibitors enable row level security;

do $$ begin
   execute 'drop policy if exists event_exhibitors_tenant on public.event_exhibitors';
   execute 'create policy event_exhibitors_tenant on public.event_exhibitors for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_sponsors enable row level security;

do $$ begin
   execute 'drop policy if exists event_sponsors_tenant on public.event_sponsors';
   execute 'create policy event_sponsors_tenant on public.event_sponsors for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_documents enable row level security;

do $$ begin
   execute 'drop policy if exists event_documents_tenant on public.event_documents';
   execute 'create policy event_documents_tenant on public.event_documents for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_incidents enable row level security;

do $$ begin
   execute 'drop policy if exists event_incidents_tenant on public.event_incidents';
   execute 'create policy event_incidents_tenant on public.event_incidents for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.event_octane_configs enable row level security;

do $$ begin
   execute 'drop policy if exists event_octane_configs_tenant on public.event_octane_configs';
   execute 'create policy event_octane_configs_tenant on public.event_octane_configs for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.products enable row level security;

do $$ begin
   execute 'drop policy if exists products_tenant on public.products';
   execute 'create policy products_tenant on public.products for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.product_variants enable row level security;

do $$ begin
   execute 'drop policy if exists product_variants_tenant on public.product_variants';
   execute 'create policy product_variants_tenant on public.product_variants for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.stock_locations enable row level security;

do $$ begin
   execute 'drop policy if exists stock_locations_tenant on public.stock_locations';
   execute 'create policy stock_locations_tenant on public.stock_locations for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.stock_lots enable row level security;

do $$ begin
   execute 'drop policy if exists stock_lots_tenant on public.stock_lots';
   execute 'create policy stock_lots_tenant on public.stock_lots for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.stock_movements enable row level security;

do $$ begin
   execute 'drop policy if exists stock_movements_tenant on public.stock_movements';
   execute 'create policy stock_movements_tenant on public.stock_movements for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.stock_reservations enable row level security;

do $$ begin
   execute 'drop policy if exists stock_reservations_tenant on public.stock_reservations';
   execute 'create policy stock_reservations_tenant on public.stock_reservations for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

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

do $$ begin
   execute 'drop policy if exists document_versions_tenant on public.document_versions';
   execute 'create policy document_versions_tenant on public.document_versions for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.document_links enable row level security;

do $$ begin
   execute 'drop policy if exists document_links_tenant on public.document_links';
   execute 'create policy document_links_tenant on public.document_links for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.document_approvals enable row level security;

do $$ begin
   execute 'drop policy if exists document_approvals_tenant on public.document_approvals';
   execute 'create policy document_approvals_tenant on public.document_approvals for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.document_access_log enable row level security;

do $$ begin
   execute 'drop policy if exists document_access_log_tenant on public.document_access_log';
   execute 'create policy document_access_log_tenant on public.document_access_log for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.document_ocr enable row level security;

do $$ begin
   execute 'drop policy if exists document_ocr_tenant on public.document_ocr';
   execute 'create policy document_ocr_tenant on public.document_ocr for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.annual_books enable row level security;

do $$ begin
   execute 'drop policy if exists annual_books_tenant on public.annual_books';
   execute 'create policy annual_books_tenant on public.annual_books for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.annual_book_items enable row level security;

do $$ begin
   execute 'drop policy if exists annual_book_items_tenant on public.annual_book_items';
   execute 'create policy annual_book_items_tenant on public.annual_book_items for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.announcements enable row level security;

do $$ begin
   execute 'drop policy if exists announcements_tenant on public.announcements';
   execute 'create policy announcements_tenant on public.announcements for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.announcement_recipients enable row level security;

do $$ begin
   execute 'drop policy if exists announcement_recipients_tenant on public.announcement_recipients';
   execute 'create policy announcement_recipients_tenant on public.announcement_recipients for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.polls enable row level security;

do $$ begin
   execute 'drop policy if exists polls_tenant on public.polls';
   execute 'create policy polls_tenant on public.polls for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.poll_options enable row level security;

do $$ begin
   execute 'drop policy if exists poll_options_tenant on public.poll_options';
   execute 'create policy poll_options_tenant on public.poll_options for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.poll_votes enable row level security;

do $$ begin
   execute 'drop policy if exists poll_votes_tenant on public.poll_votes';
   execute 'create policy poll_votes_tenant on public.poll_votes for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.notifications enable row level security;

do $$ begin
   execute 'drop policy if exists notifications_tenant on public.notifications';
   execute 'create policy notifications_tenant on public.notifications for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.activity_feed enable row level security;

do $$ begin
   execute 'drop policy if exists activity_feed_tenant on public.activity_feed';
   execute 'create policy activity_feed_tenant on public.activity_feed for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.audit_log enable row level security;

do $$ begin
   execute 'drop policy if exists audit_log_tenant on public.audit_log';
   execute 'create policy audit_log_tenant on public.audit_log for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.imports enable row level security;

do $$ begin
   execute 'drop policy if exists imports_tenant on public.imports';
   execute 'create policy imports_tenant on public.imports for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.import_rows enable row level security;

do $$ begin
   execute 'drop policy if exists import_rows_tenant on public.import_rows';
   execute 'create policy import_rows_tenant on public.import_rows for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

alter table public.exports enable row level security;

do $$ begin
   execute 'drop policy if exists exports_tenant on public.exports';
   execute 'create policy exports_tenant on public.exports for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))';
  exception when undefined_column then null; end $$;

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
left join public.stock_movements sm on sm.variant_id=pv.id
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

grant usage on schema public to authenticated;
grant select,insert,update,delete on all tables in schema public to authenticated;
grant usage,select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
insert into public.schema_migrations_bob(version,checksum) values('1.0.0-dev.1','generated-from-blueprint-v1') on conflict(version) do nothing;
