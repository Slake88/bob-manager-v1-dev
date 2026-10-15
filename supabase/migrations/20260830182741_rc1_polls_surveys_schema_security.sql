create table public.polls (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  title text not null check (length(trim(title)) between 3 and 200),
  description text,
  poll_type text not null default 'vote' check (poll_type in ('vote','survey')),
  anonymous boolean not null default true,
  multiple_choice boolean not null default false,
  show_results_before_close boolean not null default false,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  status text not null default 'draft' check (status in ('draft','published','closed','cancelled')),
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint polls_window_check check (ends_at is null or ends_at > starts_at),
  unique (id, club_id)
);

create table public.poll_options (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  poll_id uuid not null,
  label text not null check (length(trim(label)) between 1 and 300),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (id, poll_id, club_id),
  constraint poll_options_poll_fk foreign key (poll_id, club_id)
    references public.polls(id, club_id) on delete cascade
);

create table public.poll_votes (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  poll_id uuid not null,
  option_id uuid not null,
  profile_id uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  single_choice_guard boolean not null default true,
  created_at timestamptz not null default now(),
  constraint poll_votes_poll_fk foreign key (poll_id, club_id)
    references public.polls(id, club_id) on delete cascade,
  constraint poll_votes_option_fk foreign key (option_id, poll_id, club_id)
    references public.poll_options(id, poll_id, club_id) on delete restrict
);

create table public.poll_result_counts (
  club_id uuid not null,
  poll_id uuid not null,
  option_id uuid not null,
  vote_count bigint not null default 0 check (vote_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (poll_id, option_id),
  constraint poll_result_counts_poll_fk foreign key (poll_id, club_id)
    references public.polls(id, club_id) on delete cascade,
  constraint poll_result_counts_option_fk foreign key (option_id, poll_id, club_id)
    references public.poll_options(id, poll_id, club_id) on delete cascade
);

create index polls_club_status_time_idx on public.polls(club_id, status, starts_at desc);
create index polls_club_ends_idx on public.polls(club_id, ends_at) where ends_at is not null;
create index poll_options_poll_sort_idx on public.poll_options(poll_id, sort_order, id);
create unique index poll_options_label_unique_idx on public.poll_options(poll_id, lower(trim(label)));
create index poll_votes_poll_option_idx on public.poll_votes(poll_id, option_id);
create index poll_votes_profile_idx on public.poll_votes(profile_id, poll_id);
create unique index poll_votes_one_option_per_profile_idx on public.poll_votes(poll_id, profile_id, option_id);
create unique index poll_votes_single_choice_idx on public.poll_votes(poll_id, profile_id) where single_choice_guard;
create index poll_result_counts_club_poll_idx on public.poll_result_counts(club_id, poll_id);

create or replace function public.poll_member_eligible_internal_v1(p_club uuid, p_profile uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists (
    select 1
    from public.club_memberships cm
    where cm.club_id=p_club
      and cm.profile_id=p_profile
      and cm.active=true
      and lower(cm.access_role) not in ('prospect','unknown')
  ) and public.profile_has_club_permission(p_club,p_profile,'viewCommunication');
$$;
revoke all on function public.poll_member_eligible_internal_v1(uuid,uuid) from public,anon,authenticated;

create or replace function public.poll_guard_update_internal_v1()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_options integer;
begin
  if old.status <> 'draft' and (
    new.club_id is distinct from old.club_id or
    new.title is distinct from old.title or
    new.description is distinct from old.description or
    new.poll_type is distinct from old.poll_type or
    new.anonymous is distinct from old.anonymous or
    new.multiple_choice is distinct from old.multiple_choice or
    new.show_results_before_close is distinct from old.show_results_before_close or
    new.starts_at is distinct from old.starts_at or
    new.ends_at is distinct from old.ends_at or
    new.created_by is distinct from old.created_by
  ) then
    raise exception 'Uma votação publicada já não pode ser alterada; apenas encerrada ou cancelada.';
  end if;

  if old.status='draft' and new.status not in ('draft','published','cancelled') then
    raise exception 'Transição de estado inválida.';
  elsif old.status='published' and new.status not in ('published','closed','cancelled') then
    raise exception 'Transição de estado inválida.';
  elsif old.status in ('closed','cancelled') and new.status is distinct from old.status then
    raise exception 'Uma votação encerrada ou cancelada não pode ser reaberta.';
  end if;

  if old.status='draft' and new.status='published' then
    select count(*) into v_options from public.poll_options where poll_id=old.id;
    if v_options < 2 then raise exception 'São necessárias pelo menos duas opções para publicar.'; end if;
    if new.ends_at is not null and new.ends_at <= new.starts_at then
      raise exception 'O fecho tem de ser posterior à abertura.';
    end if;
  end if;

  new.updated_at:=now();
  return new;
end $$;
revoke all on function public.poll_guard_update_internal_v1() from public,anon,authenticated;
create trigger polls_guard_update before update on public.polls
for each row execute function public.poll_guard_update_internal_v1();

create or replace function public.poll_option_guard_internal_v1()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_poll uuid; v_club uuid; v_status text;
begin
  v_poll:=coalesce(new.poll_id,old.poll_id);
  v_club:=coalesce(new.club_id,old.club_id);
  select status into v_status from public.polls where id=v_poll and club_id=v_club;
  if v_status is null then raise exception 'Votação não encontrada.'; end if;
  if v_status <> 'draft' then raise exception 'As opções só podem ser alteradas enquanto a votação está em rascunho.'; end if;
  return coalesce(new,old);
end $$;
revoke all on function public.poll_option_guard_internal_v1() from public,anon,authenticated;
create trigger poll_options_guard before insert or update or delete on public.poll_options
for each row execute function public.poll_option_guard_internal_v1();

create or replace function public.poll_vote_validate_internal_v1()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare p public.polls%rowtype;
begin
  if auth.uid() is null or new.profile_id is distinct from auth.uid() then
    raise exception 'O voto só pode ser registado pelo próprio utilizador.';
  end if;
  select * into p from public.polls where id=new.poll_id and club_id=new.club_id;
  if not found then raise exception 'Votação não encontrada.'; end if;
  if p.status <> 'published' or now() < p.starts_at or (p.ends_at is not null and now() >= p.ends_at) then
    raise exception 'A votação não está aberta.';
  end if;
  if not public.poll_member_eligible_internal_v1(new.club_id,new.profile_id) then
    raise exception 'Utilizador não elegível para votar.';
  end if;
  if not exists(select 1 from public.poll_options o where o.id=new.option_id and o.poll_id=new.poll_id and o.club_id=new.club_id) then
    raise exception 'Opção inválida para esta votação.';
  end if;
  new.single_choice_guard:=not p.multiple_choice;
  new.created_at:=now();
  return new;
end $$;
revoke all on function public.poll_vote_validate_internal_v1() from public,anon,authenticated;
create trigger poll_votes_validate before insert on public.poll_votes
for each row execute function public.poll_vote_validate_internal_v1();

create or replace function public.poll_vote_count_internal_v1()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  insert into public.poll_result_counts(club_id,poll_id,option_id,vote_count,updated_at)
  values(new.club_id,new.poll_id,new.option_id,1,now())
  on conflict (poll_id,option_id)
  do update set vote_count=public.poll_result_counts.vote_count+1,updated_at=now();
  return new;
end $$;
revoke all on function public.poll_vote_count_internal_v1() from public,anon,authenticated;
create trigger poll_votes_count after insert on public.poll_votes
for each row execute function public.poll_vote_count_internal_v1();

alter table public.polls enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;
alter table public.poll_result_counts enable row level security;

create policy polls_select on public.polls for select to authenticated using (
  public.has_club_permission(club_id,'manageCommunication') or
  (status in ('published','closed') and public.poll_member_eligible_internal_v1(club_id,(select auth.uid())))
);
create policy polls_insert on public.polls for insert to authenticated with check (
  public.has_club_permission(club_id,'manageCommunication') and created_by=(select auth.uid()) and status='draft'
);
create policy polls_update on public.polls for update to authenticated using (
  public.has_club_permission(club_id,'manageCommunication')
) with check (public.has_club_permission(club_id,'manageCommunication'));
create policy polls_delete on public.polls for delete to authenticated using (
  status='draft' and public.has_club_permission(club_id,'manageCommunication')
);

create policy poll_options_select on public.poll_options for select to authenticated using (
  exists(select 1 from public.polls p where p.id=poll_id and p.club_id=club_id)
);
create policy poll_options_insert on public.poll_options for insert to authenticated with check (
  public.has_club_permission(club_id,'manageCommunication') and
  exists(select 1 from public.polls p where p.id=poll_id and p.club_id=club_id and p.status='draft')
);
create policy poll_options_update on public.poll_options for update to authenticated using (
  public.has_club_permission(club_id,'manageCommunication') and
  exists(select 1 from public.polls p where p.id=poll_id and p.club_id=club_id and p.status='draft')
) with check (
  public.has_club_permission(club_id,'manageCommunication') and
  exists(select 1 from public.polls p where p.id=poll_id and p.club_id=club_id and p.status='draft')
);
create policy poll_options_delete on public.poll_options for delete to authenticated using (
  public.has_club_permission(club_id,'manageCommunication') and
  exists(select 1 from public.polls p where p.id=poll_id and p.club_id=club_id and p.status='draft')
);

create policy poll_votes_select on public.poll_votes for select to authenticated using (
  profile_id=(select auth.uid()) or
  (public.has_club_permission(club_id,'manageCommunication') and exists(
    select 1 from public.polls p where p.id=poll_id and p.club_id=club_id and p.anonymous=false
  ))
);
create policy poll_votes_insert on public.poll_votes for insert to authenticated with check (
  profile_id=(select auth.uid()) and public.poll_member_eligible_internal_v1(club_id,(select auth.uid()))
);

create policy poll_result_counts_select on public.poll_result_counts for select to authenticated using (
  exists(
    select 1 from public.polls p
    where p.id=poll_id and p.club_id=club_id
      and (
        public.has_club_permission(p.club_id,'manageCommunication') or
        (public.poll_member_eligible_internal_v1(p.club_id,(select auth.uid())) and (
          p.status='closed' or
          (p.status='published' and (p.show_results_before_close=true or (p.ends_at is not null and p.ends_at<=now())))
        ))
      )
  )
);

revoke all on public.polls,public.poll_options,public.poll_votes,public.poll_result_counts from public,anon,authenticated;
grant select,insert,update,delete on public.polls to authenticated;
grant select,insert,update,delete on public.poll_options to authenticated;
grant select,insert on public.poll_votes to authenticated;
grant select on public.poll_result_counts to authenticated;
