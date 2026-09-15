insert into public.treasury_accounts (
  club_id,
  name,
  account_type,
  opening_balance,
  active,
  icon,
  allows_negative
)
select
  club.id,
  'Quotas',
  'fund',
  0,
  true,
  '👥',
  false
from public.clubs club
where not exists (
  select 1
  from public.treasury_accounts account
  where account.club_id = club.id
    and lower(account.name) = 'quotas'
);

create or replace function public.register_fee_payment_v1(
  target_club uuid,
  p_obligation uuid,
  p_amount numeric,
  p_payment_method text,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  obligation public.fee_obligations%rowtype;
  member_name text;
  quotas_account_id uuid;
  transaction_id uuid;
  payment_id uuid;
  new_paid numeric;
  new_status public.fee_status;
begin
  if not public.has_club_role(
    target_club,
    array['treasurer', 'secretary', 'admin', 'super_admin']
  ) then
    raise exception 'Sem autorização para registar pagamentos de quotas.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'O valor do pagamento deve ser superior a zero.';
  end if;

  select *
  into obligation
  from public.fee_obligations
  where id = p_obligation
    and club_id = target_club
  for update;

  if not found then
    raise exception 'Quota não encontrada.';
  end if;

  if obligation.status in ('paid', 'exempt', 'cancelled') then
    raise exception 'Esta quota não aceita novos pagamentos.';
  end if;

  if obligation.paid_amount + p_amount > obligation.amount then
    raise exception 'O pagamento excede o valor em dívida.';
  end if;

  select full_name
  into member_name
  from public.members
  where id = obligation.member_id
    and club_id = target_club;

  select id
  into quotas_account_id
  from public.treasury_accounts
  where club_id = target_club
    and lower(name) = 'quotas'
    and active = true
  order by created_at
  limit 1;

  if quotas_account_id is null then
    raise exception 'A conta Quotas não está disponível.';
  end if;

  insert into public.treasury_transactions (
    club_id,
    kind,
    account_id,
    transaction_date,
    description,
    amount,
    payment_method,
    source_type,
    source_id,
    created_by
  )
  values (
    target_club,
    'income',
    quotas_account_id,
    current_date,
    'Pagamento de quota - ' || coalesce(member_name, 'Membro'),
    p_amount,
    nullif(trim(p_payment_method), ''),
    'fee_obligation',
    p_obligation,
    auth.uid()
  )
  returning id into transaction_id;

  insert into public.fee_payments (
    club_id,
    obligation_id,
    transaction_id,
    amount,
    paid_at,
    received_by,
    notes
  )
  values (
    target_club,
    p_obligation,
    transaction_id,
    p_amount,
    now(),
    auth.uid(),
    p_notes
  )
  returning id into payment_id;

  new_paid := obligation.paid_amount + p_amount;
  new_status := case
    when new_paid >= obligation.amount then 'paid'::public.fee_status
    else 'partial'::public.fee_status
  end;

  update public.fee_obligations
  set paid_amount = new_paid,
      status = new_status
  where id = p_obligation;

  return payment_id;
end;
$$;

revoke all on function public.register_fee_payment_v1(
  uuid,
  uuid,
  numeric,
  text,
  text
) from public, anon;

grant execute on function public.register_fee_payment_v1(
  uuid,
  uuid,
  numeric,
  text,
  text
) to authenticated;

alter table public.fee_obligations enable row level security;
alter table public.fee_payments enable row level security;

drop policy if exists fee_obligations_access on public.fee_obligations;
drop policy if exists fees_manage on public.fee_obligations;
drop policy if exists fees_read on public.fee_obligations;
drop policy if exists fee_payments_access on public.fee_payments;

create policy fee_obligations_select
on public.fee_obligations
for select
to authenticated
using (
  public.has_club_role(
    club_id,
    array['treasurer', 'secretary', 'admin', 'super_admin']
  )
  or exists (
    select 1
    from public.members member
    where member.id = fee_obligations.member_id
      and member.profile_id = auth.uid()
  )
);

create policy fee_obligations_insert
on public.fee_obligations
for insert
to authenticated
with check (
  public.has_club_role(
    club_id,
    array['treasurer', 'secretary', 'admin', 'super_admin']
  )
);

create policy fee_obligations_update
on public.fee_obligations
for update
to authenticated
using (
  public.has_club_role(
    club_id,
    array['treasurer', 'secretary', 'admin', 'super_admin']
  )
)
with check (
  public.has_club_role(
    club_id,
    array['treasurer', 'secretary', 'admin', 'super_admin']
  )
);

create policy fee_payments_select
on public.fee_payments
for select
to authenticated
using (
  public.has_club_role(
    club_id,
    array['treasurer', 'secretary', 'admin', 'super_admin']
  )
  or exists (
    select 1
    from public.fee_obligations obligation
    join public.members member
      on member.id = obligation.member_id
    where obligation.id = fee_payments.obligation_id
      and member.profile_id = auth.uid()
  )
);
