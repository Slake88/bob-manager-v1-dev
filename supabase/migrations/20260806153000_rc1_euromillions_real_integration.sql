alter table public.euromillions_participations
  add column if not exists billing_frequency text not null default 'weekly',
  add column if not exists numbers integer[] not null default '{}'::integer[],
  add column if not exists stars integer[] not null default '{}'::integer[],
  add column if not exists paid_amount numeric not null default 0,
  add column if not exists balance numeric not null default 0,
  add column if not exists active boolean not null default true,
  add column if not exists payment_method text,
  add column if not exists transaction_id uuid references public.treasury_transactions(id);

insert into public.treasury_accounts (
  club_id, name, account_type, opening_balance, opening_date,
  active, icon, allows_negative
)
select c.id, 'Euromilhões', 'internal', 0, current_date, true, '🍀', false
from public.clubs c
where not exists (
  select 1
  from public.treasury_accounts a
  where a.club_id = c.id and lower(a.name) = lower('Euromilhões')
);

create or replace function public.ensure_euromillions_open_draw_v1(
  target_club uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  result_id uuid;
  current_week integer := extract(week from current_date)::integer;
begin
  if not public.has_club_role(
    target_club,
    array['treasurer', 'admin', 'super_admin']
  ) then
    raise exception 'Sem autorização.';
  end if;

  select id into result_id
  from public.euromillions_draws
  where club_id = target_club and status = 'open'
  order by created_at desc
  limit 1;

  if result_id is null then
    insert into public.euromillions_draws (
      club_id, week, start_date, end_date,
      unit_cost, total_bet, prize, status
    ) values (
      target_club, current_week, current_date, current_date + 6,
      0, 0, 0, 'open'
    ) returning id into result_id;
  end if;

  return result_id;
end;
$$;

create or replace function public.register_euromillions_payment_v1(
  target_club uuid,
  participation_id uuid,
  payment_amount numeric,
  p_payment_method text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.euromillions_participations%rowtype;
  draw_club uuid;
  target_account uuid;
  new_transaction uuid;
begin
  if not public.has_club_role(
    target_club,
    array['treasurer', 'admin', 'super_admin']
  ) then
    raise exception 'Sem autorização.';
  end if;

  if payment_amount <= 0 then
    raise exception 'O valor deve ser superior a zero.';
  end if;

  select ep.* into p
  from public.euromillions_participations ep
  where ep.id = participation_id
  for update;

  if p.id is null then
    raise exception 'Participação não encontrada.';
  end if;

  select club_id into draw_club
  from public.euromillions_draws
  where id = p.draw_id;

  if draw_club is distinct from target_club then
    raise exception 'Participação inválida.';
  end if;

  if payment_amount > p.balance then
    raise exception 'O pagamento excede o saldo pendente.';
  end if;

  select id into target_account
  from public.treasury_accounts
  where club_id = target_club
    and lower(name) = lower('Euromilhões')
    and active = true
  limit 1;

  if target_account is null then
    raise exception 'Conta Euromilhões não encontrada.';
  end if;

  insert into public.treasury_transactions (
    club_id, kind, account_id, transaction_date, description,
    amount, payment_method, source_type, source_id, created_by
  ) values (
    target_club, 'income', target_account, current_date,
    'Pagamento Euromilhões', payment_amount, p_payment_method,
    'euromillions_participation', participation_id, auth.uid()
  ) returning id into new_transaction;

  update public.euromillions_participations
  set paid_amount = paid_amount + payment_amount,
      balance = greatest(balance - payment_amount, 0),
      paid = (balance - payment_amount <= 0),
      paid_at = case
        when balance - payment_amount <= 0 then now()
        else paid_at
      end,
      payment_method = p_payment_method,
      transaction_id = new_transaction
  where id = participation_id;

  return new_transaction;
end;
$$;

revoke all on function public.ensure_euromillions_open_draw_v1(uuid)
  from public, anon;
revoke all on function public.register_euromillions_payment_v1(
  uuid, uuid, numeric, text
) from public, anon;

grant execute on function public.ensure_euromillions_open_draw_v1(uuid)
  to authenticated;
grant execute on function public.register_euromillions_payment_v1(
  uuid, uuid, numeric, text
) to authenticated;
