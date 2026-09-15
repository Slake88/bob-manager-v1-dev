alter table public.documents add column if not exists description text;
alter table public.documents add column if not exists document_date date;
alter table public.documents add column if not exists version text;
alter table public.documents add column if not exists status text not null default 'active';
alter table public.documents add column if not exists tags text;
alter table public.documents add column if not exists original_file_name text;
alter table public.documents add column if not exists mime_type text;
alter table public.documents add column if not exists file_size bigint;
alter table public.documents add column if not exists updated_at timestamptz not null default now();

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'club-documents',
  'club-documents',
  false,
  20971520,
  array[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

alter table public.documents enable row level security;

drop policy if exists documents_access on public.documents;
drop policy if exists documents_read on public.documents;
drop policy if exists documents_select on public.documents;
drop policy if exists documents_insert on public.documents;
drop policy if exists documents_update on public.documents;
drop policy if exists documents_delete on public.documents;

create policy documents_select
on public.documents
for select
to authenticated
using (
  has_club_access(club_id)
  and (
    sensitive = false
    or has_club_role(club_id, array['secretary', 'admin', 'super_admin'])
  )
);

create policy documents_insert
on public.documents
for insert
to authenticated
with check (
  has_club_role(club_id, array['secretary', 'admin', 'super_admin'])
  and created_by = auth.uid()
);

create policy documents_update
on public.documents
for update
to authenticated
using (has_club_role(club_id, array['secretary', 'admin', 'super_admin']))
with check (has_club_role(club_id, array['secretary', 'admin', 'super_admin']));

create policy documents_delete
on public.documents
for delete
to authenticated
using (has_club_role(club_id, array['admin', 'super_admin']));

drop policy if exists club_documents_select on storage.objects;
drop policy if exists club_documents_insert on storage.objects;
drop policy if exists club_documents_update on storage.objects;
drop policy if exists club_documents_delete on storage.objects;

create policy club_documents_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'club-documents'
  and exists (
    select 1
    from public.documents d
    where d.storage_path = name
      and has_club_access(d.club_id)
      and (
        d.sensitive = false
        or has_club_role(d.club_id, array['secretary', 'admin', 'super_admin'])
      )
  )
);

create policy club_documents_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'club-documents'
  and has_club_role(
    ((storage.foldername(name))[1])::uuid,
    array['secretary', 'admin', 'super_admin']
  )
);

create policy club_documents_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'club-documents'
  and has_club_role(
    ((storage.foldername(name))[1])::uuid,
    array['secretary', 'admin', 'super_admin']
  )
)
with check (
  bucket_id = 'club-documents'
  and has_club_role(
    ((storage.foldername(name))[1])::uuid,
    array['secretary', 'admin', 'super_admin']
  )
);

create policy club_documents_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'club-documents'
  and has_club_role(
    ((storage.foldername(name))[1])::uuid,
    array['secretary', 'admin', 'super_admin']
  )
);
