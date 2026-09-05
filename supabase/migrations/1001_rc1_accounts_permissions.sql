-- BOB Manager RC1: consolidação da tesouraria apenas com contas.

alter table public.financial_accounts
  add column if not exists icon text not null default '💰',
  add column if not exists color text not null default '#0C18D2',
  add column if not exists display_order integer not null default 999,
  add column if not exists allows_negative boolean not null default false,
  add column if not exists protected boolean not null default false,
  add column if not exists created_by uuid,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz;

update public.financial_accounts
set allows_negative = (lower(name) = 'caixa')
where allows_negative is distinct from (lower(name) = 'caixa');

create unique index if not exists uq_financial_accounts_club_name_active
  on public.financial_accounts(club_id, lower(name))
  where active;

create or replace function public.account_balance(
  target_club uuid,
  target_account uuid
) returns numeric
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(a.opening_balance, 0)
    + coalesce(sum(
        case
          when t.kind = 'income' and t.account_id = a.id then t.amount
          when t.kind = 'expense' and t.account_id = a.id then -t.amount
          when t.kind = 'transfer' and t.account_id = a.id then -t.amount
          when t.kind = 'transfer' and t.destination_account_id = a.id then t.amount
          else 0
        end
      ), 0)
  from public.financial_accounts a
  left join public.financial_transactions t
    on t.club_id = a.club_id
   and (t.account_id = a.id or t.destination_account_id = a.id)
   and coalesce(t.status, 'confirmed') = 'confirmed'
  where a.club_id = target_club
    and a.id = target_account
  group by a.id, a.opening_balance;
$$;

create or replace function public.transfer_between_accounts(
  target_club uuid,
  source_account uuid,
  destination_account uuid,
  transfer_amount numeric,
  transfer_description text default null
) returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  source_row public.financial_accounts%rowtype;
  movement_id uuid;
  source_balance numeric;
begin
  if source_account = destination_account then
    raise exception 'As contas de origem e destino têm de ser diferentes.';
  end if;
  if transfer_amount is null or transfer_amount <= 0 then
    raise exception 'O valor deve ser superior a zero.';
  end if;

  select * into source_row
  from public.financial_accounts
  where id = source_account and club_id = target_club and active
  for update;

  if not found then
    raise exception 'Conta de origem inválida.';
  end if;

  perform 1 from public.financial_accounts
  where id = destination_account and club_id = target_club and active;
  if not found then
    raise exception 'Conta de destino inválida.';
  end if;

  source_balance := public.account_balance(target_club, source_account);
  if not source_row.allows_negative and source_balance < transfer_amount then
    raise exception 'Saldo insuficiente na conta %.', source_row.name;
  end if;

  insert into public.financial_transactions(
    club_id, kind, status, transaction_date, account_id,
    destination_account_id, description, amount, created_by, confirmed_at
  ) values (
    target_club, 'transfer', 'confirmed', current_date, source_account,
    destination_account, coalesce(nullif(trim(transfer_description), ''),
    'Transferência entre contas'), transfer_amount, auth.uid(), now()
  ) returning id into movement_id;

  return movement_id;
end;
$$;

-- A tabela funds é mantida apenas para compatibilidade histórica nesta migração.
-- A aplicação RC1 deixa de a consultar ou apresentar.
