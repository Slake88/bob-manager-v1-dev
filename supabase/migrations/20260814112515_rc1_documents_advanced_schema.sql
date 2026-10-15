alter table public.documents
  add column if not exists scope text not null default 'club',
  add column if not exists owner_profile_id uuid references public.profiles(id) on delete set null,
  add column if not exists event_id uuid references public.events(id) on delete set null,
  add column if not exists current_version_id uuid,
  add column if not exists requires_approval boolean not null default false,
  add column if not exists approval_status text not null default 'not_required',
  add column if not exists ocr_status text not null default 'not_requested',
  add column if not exists archived_at timestamptz;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='documents_scope_check') then
    alter table public.documents add constraint documents_scope_check check (scope in ('club','leadership','personal','event_gallery','annual_book'));
  end if;
  if not exists (select 1 from pg_constraint where conname='documents_approval_status_check') then
    alter table public.documents add constraint documents_approval_status_check check (approval_status in ('not_required','pending','approved','rejected'));
  end if;
  if not exists (select 1 from pg_constraint where conname='documents_ocr_status_check') then
    alter table public.documents add constraint documents_ocr_status_check check (ocr_status in ('not_requested','pending','processing','ready','unconfigured','failed'));
  end if;
end $$;

update public.documents
set scope = case when sensitive then 'leadership' else 'club' end
where scope='club';

create table if not exists public.document_versions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  document_id uuid not null references public.documents(id) on delete cascade,
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

create unique index if not exists document_versions_one_current_idx
  on public.document_versions(document_id) where is_current;
create index if not exists document_versions_club_document_idx
  on public.document_versions(club_id,document_id,version_no desc);

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
create index if not exists document_links_target_idx on public.document_links(club_id,linked_entity_type,linked_entity_id);

create table if not exists public.document_approvals (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  document_id uuid not null references public.documents(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  requested_by uuid not null default auth.uid(),
  requested_at timestamptz not null default now(),
  decided_by uuid,
  decided_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists document_approvals_one_pending_idx on public.document_approvals(document_id) where status='pending';
create index if not exists document_approvals_club_status_idx on public.document_approvals(club_id,status,requested_at desc);

create table if not exists public.document_ocr (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  document_id uuid not null references public.documents(id) on delete cascade,
  version_id uuid references public.document_versions(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','processing','ready','unconfigured','failed','cancelled')),
  provider text,
  model text,
  raw_text text,
  confidence numeric(5,4) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  error_message text,
  started_at timestamptz,
  completed_at timestamptz,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists document_ocr_document_idx on public.document_ocr(document_id,created_at desc);
create index if not exists document_ocr_club_status_idx on public.document_ocr(club_id,status,created_at desc);

create table if not exists public.document_access_log (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  document_id uuid not null references public.documents(id) on delete cascade,
  version_id uuid references public.document_versions(id) on delete set null,
  profile_id uuid not null default auth.uid(),
  action text not null check (action in ('view','download','signed_url','share')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists document_access_log_document_idx on public.document_access_log(document_id,created_at desc);
create index if not exists document_access_log_profile_idx on public.document_access_log(profile_id,created_at desc);

create table if not exists public.annual_books (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  year integer not null check (year between 2000 and 2200),
  title text not null,
  description text,
  status text not null default 'draft' check (status in ('draft','published','archived')),
  cover_document_id uuid references public.documents(id) on delete set null,
  published_at timestamptz,
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(club_id,year)
);

create table if not exists public.annual_book_items (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  annual_book_id uuid not null references public.annual_books(id) on delete cascade,
  sequence_no integer not null check (sequence_no > 0),
  item_type text not null default 'custom' check (item_type in ('custom','document','event','member','timeline')),
  title text not null,
  body text,
  document_id uuid references public.documents(id) on delete set null,
  linked_entity_type text,
  linked_entity_id uuid,
  event_date date,
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(annual_book_id,sequence_no)
);
create index if not exists annual_book_items_book_idx on public.annual_book_items(annual_book_id,sequence_no);
create index if not exists annual_book_items_document_idx on public.annual_book_items(document_id);

alter table public.documents
  add constraint documents_current_version_fkey foreign key (current_version_id) references public.document_versions(id) on delete set null;

create index if not exists documents_scope_idx on public.documents(club_id,scope,created_at desc);
create index if not exists documents_owner_idx on public.documents(owner_profile_id,created_at desc) where owner_profile_id is not null;
create index if not exists documents_event_gallery_idx on public.documents(event_id,created_at desc) where event_id is not null;
create index if not exists documents_current_version_idx on public.documents(current_version_id) where current_version_id is not null;

alter table public.document_versions enable row level security;
alter table public.document_links enable row level security;
alter table public.document_approvals enable row level security;
alter table public.document_ocr enable row level security;
alter table public.document_access_log enable row level security;
alter table public.annual_books enable row level security;
alter table public.annual_book_items enable row level security;

revoke all on table public.document_versions, public.document_links, public.document_approvals, public.document_ocr, public.document_access_log, public.annual_books, public.annual_book_items from anon;
grant select,insert,update,delete on table public.document_versions, public.document_links, public.document_approvals, public.document_ocr, public.annual_books, public.annual_book_items to authenticated;
grant select,insert on table public.document_access_log to authenticated;
