create or replace function public.treasury_account_balance_v1(
  target_account uuid
)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select
    a.opening_balance
    + coalesce(sum(
        case
          when t.kind = 'income' and t.account_id = a.id then t.amount
          when t.kind = 'expense' and t.account_id = a.id then -t.amount
          when t.kind = 'transfer' and t.account_id = a.id then -t.amount
          when t.kind = 'transfer' and t.destination_account_id = a.id then t.amount
          else 0
        end
      ), 0)
  from public.treasury_accounts a
  left join public.treasury_transactions t
    on t.club_id = a.club_id
   and (t.account_id = a.id or t.destination_account_id = a.id)
  where a.id = target_account
  group by a.id, a.opening_balance;
$$;

create or replace function public.validate_treasury_transaction_v1()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  source_account public.treasury_accounts%rowtype;
  destination_account public.treasury_accounts%rowtype;
  source_balance numeric;
begin
  if new.amount is null or new.amount <= 0 then
    raise exception 'O valor do movimento deve ser superior a zero.';
  end if;

  select * into source_account
  from public.treasury_accounts
  where id = new.account_id
    and club_id = new.club_id
    and active = true;

  if not found then
    raise exception 'A conta de origem não existe, está inativa ou pertence a outro clube.';
  end if;

  if new.kind = 'transfer' then
    if new.destination_account_id is null then
      raise exception 'A transferência exige uma conta de destino.';
    end if;
    if new.destination_account_id = new.account_id then
      raise exception 'As contas de origem e destino têm de ser diferentes.';
    end if;

    select * into destination_account
    from public.treasury_accounts
    where id = new.destination_account_id
      and club_id = new.club_id
      and active = true;

    if not found then
      raise exception 'A conta de destino não existe, está inativa ou pertence a outro clube.';
    end if;
  elsif new.destination_account_id is not null then
    raise exception 'A conta de destino só pode ser usada numa transferência.';
  end if;

  if new.kind in ('expense', 'transfer') and not coalesce(source_account.allows_negative, false) then
    source_balance := public.treasury_account_balance_v1(new.account_id);
    if coalesce(source_balance, 0) < new.amount then
      raise exception 'Saldo insuficiente na conta %.', source_account.name;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists treasury_transactions_balance_guard on public.treasury_transactions;
create trigger treasury_transactions_balance_guard
before insert on public.treasury_transactions
for each row execute function public.validate_treasury_transaction_v1();

update public.treasury_accounts
set allows_negative = (lower(trim(name)) = 'caixa');

create or replace function public.create_transaction_v1(
  target_club uuid,
  p_kind text,
  p_account uuid,
  p_destination_account uuid,
  p_description text,
  p_amount numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  result_id uuid;
begin
  if not public.has_club_role(target_club, array['treasurer','president','vice_president','admin','super_admin']) then
    raise exception 'Sem autorização.';
  end if;
  if p_kind not in ('income','expense','transfer') then
    raise exception 'Tipo de movimento inválido.';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'O valor deve ser superior a zero.';
  end if;
  if p_description is null or btrim(p_description) = '' then
    raise exception 'A descrição é obrigatória.';
  end if;

  insert into public.treasury_transactions (
    club_id, kind, account_id, destination_account_id,
    transaction_date, description, amount, created_by
  ) values (
    target_club,
    p_kind::public.transaction_kind,
    p_account,
    case when p_kind = 'transfer' then p_destination_account else null end,
    current_date,
    btrim(p_description),
    p_amount,
    auth.uid()
  ) returning id into result_id;

  return result_id;
end;
$$;
