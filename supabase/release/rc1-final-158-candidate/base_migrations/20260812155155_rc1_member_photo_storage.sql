-- Commit 16 — Fotografia de membro em Storage privado

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'member-photos',
  'member-photos',
  false,
  5242880,
  array['image/jpeg']::text[]
)
on conflict (id) do update
set
  name = excluded.name,
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists member_photos_select on storage.objects;
drop policy if exists member_photos_insert on storage.objects;
drop policy if exists member_photos_update on storage.objects;
drop policy if exists member_photos_delete on storage.objects;

create policy member_photos_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'member-photos'
  and (storage.foldername(name))[2] = 'members'
  and exists (
    select 1
    from public.members m
    where m.club_id = ((storage.foldername(name))[1])::uuid
      and m.id = ((storage.foldername(name))[3])::uuid
      and public.has_club_permission(m.club_id, 'viewMembers')
  )
);

create policy member_photos_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'member-photos'
  and (storage.foldername(name))[2] = 'members'
  and exists (
    select 1
    from public.members m
    where m.club_id = ((storage.foldername(name))[1])::uuid
      and m.id = ((storage.foldername(name))[3])::uuid
      and public.has_club_permission(m.club_id, 'manageMembers')
  )
);

create policy member_photos_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'member-photos'
  and (storage.foldername(name))[2] = 'members'
  and exists (
    select 1
    from public.members m
    where m.club_id = ((storage.foldername(name))[1])::uuid
      and m.id = ((storage.foldername(name))[3])::uuid
      and public.has_club_permission(m.club_id, 'manageMembers')
  )
)
with check (
  bucket_id = 'member-photos'
  and (storage.foldername(name))[2] = 'members'
  and exists (
    select 1
    from public.members m
    where m.club_id = ((storage.foldername(name))[1])::uuid
      and m.id = ((storage.foldername(name))[3])::uuid
      and public.has_club_permission(m.club_id, 'manageMembers')
  )
);

create policy member_photos_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'member-photos'
  and (storage.foldername(name))[2] = 'members'
  and exists (
    select 1
    from public.members m
    where m.club_id = ((storage.foldername(name))[1])::uuid
      and m.id = ((storage.foldername(name))[3])::uuid
      and public.has_club_permission(m.club_id, 'manageMembers')
  )
);
