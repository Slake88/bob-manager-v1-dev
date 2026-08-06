create table if not exists public.club_settings (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  key text not null,
  value text not null default '',
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint club_settings_key_not_blank check (length(trim(key)) > 0),
  constraint club_settings_club_key_unique unique (club_id, key)
);

alter table public.club_settings enable row level security;
drop policy if exists club_settings_read on public.club_settings;
drop policy if exists club_settings_manage on public.club_settings;
create policy club_settings_read on public.club_settings for select to authenticated
using (public.has_club_role(club_id, array['admin','super_admin']));
create policy club_settings_manage on public.club_settings for all to authenticated
using (public.has_club_role(club_id, array['admin','super_admin']))
with check (public.has_club_role(club_id, array['admin','super_admin']));

create or replace function public.dashboard_summary_rc1(target_club uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  can_financial boolean;
  members_count integer := 0;
  prospects_count integer := 0;
  outstanding numeric := 0;
  overdue_count integer := 0;
  open_events_count integer := 0;
  low_stock_count integer := 0;
  expiring_documents_count integer := 0;
  unread_announcements_count integer := 0;
  total_balance numeric := 0;
  monthly_income numeric := 0;
  monthly_expense numeric := 0;
begin
  if not public.has_club_access(target_club) then raise exception 'Sem acesso ao clube.'; end if;
  can_financial := public.has_club_role(target_club, array['treasurer','admin','super_admin']);

  select count(*) filter (where status::text not in ('former','deceased')),
         count(*) filter (where status::text = 'prospect')
    into members_count, prospects_count from public.members where club_id = target_club;
  select coalesce(sum(greatest(amount-paid_amount,0)),0),
         count(*) filter (where greatest(amount-paid_amount,0)>0 and due_date<current_date)
    into outstanding, overdue_count from public.fee_obligations where club_id=target_club;
  select count(*) into open_events_count from public.events
    where club_id=target_club and status::text not in ('completed','cancelled','archived');
  select count(*) into low_stock_count from public.products
    where club_id=target_club and active=true and (current_stock-reserved_stock)<=minimum_stock;
  select count(*) into expiring_documents_count from public.documents
    where club_id=target_club and expires_at between current_date and current_date+30;
  select count(*) into unread_announcements_count from public.announcements a
    where a.club_id=target_club and a.requires_acknowledgement=true
      and a.published_at<=now() and (a.expires_at is null or a.expires_at>now())
      and not exists (select 1 from public.announcement_acknowledgements aa
        where aa.announcement_id=a.id and aa.profile_id=auth.uid());

  if can_financial then
    select coalesce(sum(a.opening_balance
      + coalesce((select sum(case when t.kind::text='income' then t.amount when t.kind::text in ('expense','transfer') then -t.amount else 0 end)
          from public.treasury_transactions t where t.club_id=target_club and t.account_id=a.id),0)
      + coalesce((select sum(t.amount) from public.treasury_transactions t
          where t.club_id=target_club and t.kind::text='transfer' and t.destination_account_id=a.id),0)),0)
      into total_balance from public.treasury_accounts a where a.club_id=target_club and a.active=true;
    select coalesce(sum(amount) filter (where kind::text='income'),0),
           coalesce(sum(amount) filter (where kind::text='expense'),0)
      into monthly_income, monthly_expense from public.treasury_transactions
      where club_id=target_club and date_trunc('month',transaction_date::timestamp)=date_trunc('month',current_date::timestamp);
  end if;

  return jsonb_build_object(
    'members',members_count,'prospects',prospects_count,
    'total_balance',case when can_financial then total_balance else 0 end,
    'fee_outstanding',outstanding,'overdue_fees',overdue_count,
    'open_events',open_events_count,'low_stock',low_stock_count,
    'expiring_documents',expiring_documents_count,
    'unread_announcements',unread_announcements_count,
    'pending_approvals',0,
    'monthly_income',case when can_financial then monthly_income else 0 end,
    'monthly_expense',case when can_financial then monthly_expense else 0 end,
    'can_view_financial',can_financial);
end; $$;
revoke all on function public.dashboard_summary_rc1(uuid) from public, anon;
grant execute on function public.dashboard_summary_rc1(uuid) to authenticated;

alter table public.audit_log enable row level security;
drop policy if exists audit_log_access on public.audit_log;
drop policy if exists audit_read on public.audit_log;
drop policy if exists audit_insert on public.audit_log;
create policy audit_read on public.audit_log for select to authenticated
using (public.has_club_role(club_id,array['admin','super_admin']));
create policy audit_insert on public.audit_log for insert to authenticated
with check (public.has_club_role(club_id,array['admin','super_admin']) and (actor_id is null or actor_id=auth.uid()));
