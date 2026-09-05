-- Hardening: a função de autorização fica apenas para uso interno do trigger.

create or replace function public.protect_member_milestone_dates_v1()
returns trigger
language plpgsql
security definer
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

revoke all on function public.can_edit_member_milestone_dates_v1(uuid) from authenticated;
revoke all on function public.can_edit_member_milestone_dates_v1(uuid) from anon;
revoke all on function public.can_edit_member_milestone_dates_v1(uuid) from public;

revoke all on function public.protect_member_milestone_dates_v1() from authenticated;
revoke all on function public.protect_member_milestone_dates_v1() from anon;
revoke all on function public.protect_member_milestone_dates_v1() from public;
