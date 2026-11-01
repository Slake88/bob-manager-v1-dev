-- Commit 7: datas de entrada Prospect e Full Color com edição restrita.
-- Apenas Superadmin, Presidente e Vice-Presidente podem definir/alterar estes campos.

create or replace function public.can_edit_member_milestone_dates_v1(target_club uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.club_memberships cm
      where cm.club_id=target_club
        and cm.profile_id=(select auth.uid())
        and cm.active=true
        and cm.access_role in ('super_admin','president','vice_president')
    );
$$;

create or replace function public.protect_member_milestone_dates_v1()
returns trigger
language plpgsql
security invoker
set search_path=public
as $$
begin
  if tg_op='INSERT' then
    if (new.prospect_joined_at is not null or new.full_colors_at is not null)
       and not public.can_edit_member_milestone_dates_v1(new.club_id) then
      raise exception using
        errcode='42501',
        message='Apenas Superadmin, Presidente ou Vice-Presidente podem definir as datas de Prospect e Full Color.';
    end if;
  elsif tg_op='UPDATE' then
    if (new.prospect_joined_at is distinct from old.prospect_joined_at
        or new.full_colors_at is distinct from old.full_colors_at)
       and not public.can_edit_member_milestone_dates_v1(new.club_id) then
      raise exception using
        errcode='42501',
        message='Apenas Superadmin, Presidente ou Vice-Presidente podem alterar as datas de Prospect e Full Color.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists members_milestone_dates_insert_guard_v1 on public.members;
create trigger members_milestone_dates_insert_guard_v1
before insert on public.members
for each row execute function public.protect_member_milestone_dates_v1();

drop trigger if exists members_milestone_dates_update_guard_v1 on public.members;
create trigger members_milestone_dates_update_guard_v1
before update of prospect_joined_at, full_colors_at on public.members
for each row execute function public.protect_member_milestone_dates_v1();

revoke all on function public.can_edit_member_milestone_dates_v1(uuid) from public;
revoke all on function public.can_edit_member_milestone_dates_v1(uuid) from anon;
grant execute on function public.can_edit_member_milestone_dates_v1(uuid) to authenticated;

revoke all on function public.protect_member_milestone_dates_v1() from public;
revoke all on function public.protect_member_milestone_dates_v1() from anon;
revoke all on function public.protect_member_milestone_dates_v1() from authenticated;
