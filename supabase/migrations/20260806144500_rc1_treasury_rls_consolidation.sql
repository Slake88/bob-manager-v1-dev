alter table public.treasury_accounts enable row level security;
alter table public.treasury_transactions enable row level security;
alter table public.cost_centers enable row level security;

drop policy if exists treasury_accounts_access on public.treasury_accounts;
drop policy if exists treasury_accounts_read on public.treasury_accounts;
drop policy if exists treasury_accounts_select on public.treasury_accounts;
drop policy if exists treasury_accounts_insert on public.treasury_accounts;
drop policy if exists treasury_accounts_update on public.treasury_accounts;
drop policy if exists treasury_accounts_delete on public.treasury_accounts;

create policy treasury_accounts_select
on public.treasury_accounts
for select
to authenticated
using (
  public.has_club_role(
    club_id,
    array['treasurer','admin','super_admin']
  )
);

create policy treasury_accounts_insert
on public.treasury_accounts
for insert
to authenticated
with check (
  public.has_club_role(
    club_id,
    array['admin','super_admin']
  )
);

create policy treasury_accounts_update
on public.treasury_accounts
for update
to authenticated
using (
  public.has_club_role(
    club_id,
    array['admin','super_admin']
  )
)
with check (
  public.has_club_role(
    club_id,
    array['admin','super_admin']
  )
);

create policy treasury_accounts_delete
on public.treasury_accounts
for delete
to authenticated
using (
  public.has_club_role(
    club_id,
    array['admin','super_admin']
  )
);

drop policy if exists treasury_transactions_access on public.treasury_transactions;
drop policy if exists treasury_transactions_manage on public.treasury_transactions;
drop policy if exists treasury_transactions_read on public.treasury_transactions;
drop policy if exists treasury_transactions_select on public.treasury_transactions;
drop policy if exists treasury_transactions_insert on public.treasury_transactions;

create policy treasury_transactions_select
on public.treasury_transactions
for select
to authenticated
using (
  public.has_club_role(
    club_id,
    array['treasurer','admin','super_admin']
  )
);

create policy treasury_transactions_insert
on public.treasury_transactions
for insert
to authenticated
with check (
  public.has_club_role(
    club_id,
    array['treasurer','admin','super_admin']
  )
  and created_by = auth.uid()
);

drop policy if exists cost_centers_access on public.cost_centers;
drop policy if exists cost_centers_read on public.cost_centers;
drop policy if exists cost_centers_select on public.cost_centers;
drop policy if exists cost_centers_insert on public.cost_centers;
drop policy if exists cost_centers_update on public.cost_centers;
drop policy if exists cost_centers_delete on public.cost_centers;

create policy cost_centers_select
on public.cost_centers
for select
to authenticated
using (
  public.has_club_role(
    club_id,
    array['treasurer','admin','super_admin']
  )
);

create policy cost_centers_insert
on public.cost_centers
for insert
to authenticated
with check (
  public.has_club_role(
    club_id,
    array['admin','super_admin']
  )
);

create policy cost_centers_update
on public.cost_centers
for update
to authenticated
using (
  public.has_club_role(
    club_id,
    array['admin','super_admin']
  )
)
with check (
  public.has_club_role(
    club_id,
    array['admin','super_admin']
  )
);

create policy cost_centers_delete
on public.cost_centers
for delete
to authenticated
using (
  public.has_club_role(
    club_id,
    array['admin','super_admin']
  )
);

revoke all on function public.create_transaction_v1(uuid,text,uuid,uuid,text,numeric) from public;
revoke all on function public.create_transaction_v1(uuid,text,uuid,uuid,text,numeric) from anon;
grant execute on function public.create_transaction_v1(uuid,text,uuid,uuid,text,numeric) to authenticated;

revoke all on function public.treasury_account_balances_v1(uuid) from public;
revoke all on function public.treasury_account_balances_v1(uuid) from anon;
grant execute on function public.treasury_account_balances_v1(uuid) to authenticated;

revoke all on function public.treasury_account_balance_v1(uuid) from public;
revoke all on function public.treasury_account_balance_v1(uuid) from anon;
grant execute on function public.treasury_account_balance_v1(uuid) to authenticated;
