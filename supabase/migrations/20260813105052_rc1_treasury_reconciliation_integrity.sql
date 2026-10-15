-- Commit 24 follow-up — integridade server-side da reconciliação bancária.
-- Um item conciliado tem de pertencer ao mesmo clube, à conta da reconciliação
-- e ao respetivo período. A UI já filtra estes movimentos; esta trigger torna
-- a regra obrigatória também contra clientes adulterados.

create or replace function public.bank_reconciliation_item_guard_v1()
returns trigger
language plpgsql
security invoker
set search_path='public'
as $$
declare
  v_account uuid;
  v_period_start date;
  v_period_end date;
  v_status text;
  v_transaction_account uuid;
  v_transaction_destination uuid;
  v_transaction_date date;
begin
  select account_id, period_start, period_end, status
    into v_account, v_period_start, v_period_end, v_status
  from public.bank_reconciliations
  where id=new.reconciliation_id
    and club_id=new.club_id;

  if not found then
    raise exception 'A reconciliação não pertence ao clube.';
  end if;
  if v_status <> 'draft' then
    raise exception 'A reconciliação já está fechada.';
  end if;

  select account_id, destination_account_id, transaction_date
    into v_transaction_account, v_transaction_destination, v_transaction_date
  from public.treasury_transactions
  where id=new.transaction_id
    and club_id=new.club_id;

  if not found then
    raise exception 'O movimento não pertence ao clube.';
  end if;
  if v_transaction_date < v_period_start or v_transaction_date > v_period_end then
    raise exception 'O movimento está fora do período da reconciliação.';
  end if;
  if v_transaction_account is distinct from v_account
     and v_transaction_destination is distinct from v_account then
    raise exception 'O movimento não pertence à conta da reconciliação.';
  end if;

  return new;
end;
$$;

revoke all on function public.bank_reconciliation_item_guard_v1()
  from public, anon, authenticated;

drop trigger if exists trg_bank_reconciliation_item_guard_v1
  on public.bank_reconciliation_items;
create trigger trg_bank_reconciliation_item_guard_v1
before insert or update on public.bank_reconciliation_items
for each row execute function public.bank_reconciliation_item_guard_v1();