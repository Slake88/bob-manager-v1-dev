create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  title text not null,
  body text not null,
  priority text not null default 'normal'
    check (priority in ('informative','normal','important','urgent','critical')),
  audience text not null default 'all',
  published_at timestamptz not null default now(),
  expires_at timestamptz,
  requires_acknowledgement boolean not null default false,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint announcements_expiry_after_publication
    check (expires_at is null or expires_at > published_at)
);

create table if not exists public.announcement_acknowledgements (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  profile_id uuid not null,
  acknowledged_at timestamptz not null default now(),
  unique (announcement_id, profile_id)
);

create index if not exists announcements_club_publication_idx
  on public.announcements(club_id, published_at desc);
create index if not exists announcement_ack_profile_idx
  on public.announcement_acknowledgements(profile_id, announcement_id);

alter table public.announcements enable row level security;
alter table public.announcement_acknowledgements enable row level security;

drop policy if exists announcements_access on public.announcements;
drop policy if exists announcements_read on public.announcements;
drop policy if exists announcements_manage on public.announcements;
drop policy if exists announcements_insert on public.announcements;
drop policy if exists announcements_update on public.announcements;
drop policy if exists announcements_delete on public.announcements;
drop policy if exists announcement_acknowledgements_access
  on public.announcement_acknowledgements;
drop policy if exists announcement_ack_read_own
  on public.announcement_acknowledgements;
drop policy if exists announcement_ack_insert_own
  on public.announcement_acknowledgements;
drop policy if exists announcement_ack_manage_read
  on public.announcement_acknowledgements;

create policy announcements_read
on public.announcements for select to authenticated
using (public.has_club_access(club_id));

create policy announcements_insert
on public.announcements for insert to authenticated
with check (
  public.has_club_role(club_id, array['secretary','admin','super_admin'])
);

create policy announcements_update
on public.announcements for update to authenticated
using (
  public.has_club_role(club_id, array['secretary','admin','super_admin'])
)
with check (
  public.has_club_role(club_id, array['secretary','admin','super_admin'])
);

create policy announcements_delete
on public.announcements for delete to authenticated
using (public.has_club_role(club_id, array['admin','super_admin']));

create policy announcement_ack_read_own
on public.announcement_acknowledgements for select to authenticated
using (profile_id = auth.uid() and public.has_club_access(club_id));

create policy announcement_ack_insert_own
on public.announcement_acknowledgements for insert to authenticated
with check (
  profile_id = auth.uid()
  and public.has_club_access(club_id)
  and exists (
    select 1
    from public.announcements a
    where a.id = announcement_id
      and a.club_id = club_id
  )
);

create policy announcement_ack_manage_read
on public.announcement_acknowledgements for select to authenticated
using (
  public.has_club_role(club_id, array['secretary','admin','super_admin'])
);
