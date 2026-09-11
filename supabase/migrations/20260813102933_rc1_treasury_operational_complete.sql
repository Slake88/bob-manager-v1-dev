-- Commit 24 — Tesouraria Operacional Completa
-- Reversões, contas a pagar/receber, orçamentos, reconciliação bancária,
-- sessões de caixa e gestão de centros de custo.

-- 1) Permissões específicas. O trigger de Activity Feed é suspenso apenas durante
-- o seed de migration, porque migrations não têm auth.uid(). Auditoria mantém-se ativa.
alter table public.club_role_permissions disable trigger trg_activity_role_permissions;
with permissions(permission_key) as (
  values
    ('manageTreasuryPlanning'),
    ('manageCashSessions'),
    ('approveCashDifferences'),
    ('reverseTreasuryMovement')
), roles(role_key) as (
  values
    ('president'),('vice_president'),('admin'),('administrator'),('treasurer'),
    ('secretary'),('road_captain'),('inventory_manager'),('event_manager'),
    ('events_manager'),('euromillions_manager'),('prospect'),('member')
)
insert into public.club_role_permissions(club_id, role_key, permission_key, allowed)
select
  c.id,
  r.role_key,
  p.permission_key,
  case
    when r.role_key in ('president','vice_president','admin','administrator') then true
    when r.role_key='treasurer' and p.permission_key in (
      'manageTreasuryPlanning','manageCashSessions','reverseTreasuryMovement'
    ) then true
    else false
  end
from public.clubs c
cross join roles r
cross join permissions p
on conflict (club_id,role_key,permission_key) do nothing;
alter table public.club_role_permissions enable trigger trg_activity_role_permissions;

-- 2) Contas a pagar / receber.
create table public.payables (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  counterparty text not null,
  description text not null,
  due_date date not null,
  amount numeric(12,2) not null check (amount > 0),
  settled_amount numeric(12,2) not null default 0 check (settled_amount >= 0),
  status text not null default 'open' check (status in ('open','partial','paid','cancelled')),
  account_id uuid references public.treasury_accounts(id) on delete set null,
  cost_center_id uuid references public.cost_centers(id) on delete set null,
  event_id uuid references public.events(id) on delete set null,
  notes text,
  cancelled_at timestamptz,
  cancelled_by uuid,
  created_at timestamptz default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz default now(),
  updated_by uuid default auth.uid(),
  constraint payables_settlement_check check (settled_amount <= amount)
);

create table public.receivables (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  counterparty text not null,
  description text not null,
  due_date date not null,
  amount numeric(12,2) not null check (amount > 0),
  settled_amount numeric(12,2) not null default 0 check (settled_amount >= 0),
  status text not null default 'open' check (status in ('open','partial','paid','cancelled')),
  account_id uuid references public.treasury_accounts(id) on delete set null,
  cost_center_id uuid references public.cost_centers(id) on delete set null,
  event_id uuid references public.events(id) on delete set null,
  notes text,
  cancelled_at timestamptz,
  cancelled_by uuid,
  created_at timestamptz default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz default now(),
  updated_by uuid default auth.uid(),
  constraint receivables_settlement_check check (settled_amount <= amount)
);

create index idx_payables_club_status_due on public.payables(club_id,status,due_date);
create index idx_receivables_club_status_due on public.receivables(club_id,status,due_date);

-- 3) Orçamentos.
create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  name text not null,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft','approved','closed')),
  notes text,
  approved_at timestamptz,
  approved_by uuid,
  closed_at timestamptz,
  closed_by uuid,
  created_at timestamptz default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz default now(),
  updated_by uuid default auth.uid(),
  constraint budgets_period_check check (period_end >= period_start),
  unique(id,club_id)
);

create table public.budget_lines (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  budget_id uuid not null,
  label text not null,
  line_type text not null check (line_type in ('income','expense')),
  planned_amount numeric(12,2) not null default 0 check (planned_amount >= 0),
  cost_center_id uuid references public.cost_centers(id) on delete set null,
  event_id uuid references public.events(id) on delete set null,
  notes text,
  created_at timestamptz default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz default now(),
  updated_by uuid default auth.uid(),
  constraint budget_lines_budget_club_fkey foreign key (budget_id,club_id)
    references public.budgets(id,club_id) on delete cascade
);

create index idx_budgets_club_period on public.budgets(club_id,period_start,period_end);
create index idx_budget_lines_budget on public.budget_lines(budget_id);

-- 4) Reconciliação bancária.
create table public.bank_reconciliations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  account_id uuid not null references public.treasury_accounts(id) on delete restrict,
  period_start date not null,
  period_end date not null,
  statement_opening_balance numeric(12,2) not null,
  statement_closing_balance numeric(12,2) not null,
  book_closing_balance numeric(12,2),
  difference_amount numeric(12,2),
  status text not null default 'draft' check (status in ('draft','closed')),
  notes text,
  closed_at timestamptz,
  closed_by uuid,
  created_at timestamptz default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz default now(),
  updated_by uuid default auth.uid(),
  constraint bank_reconciliations_period_check check (period_end >= period_start)
);

create table public.bank_reconciliation_items (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  reconciliation_id uuid not null references public.bank_reconciliations(id) on delete cascade,
  transaction_id uuid not null references public.treasury_transactions(id) on delete restrict,
  created_at timestamptz default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz default now(),
  updated_by uuid default auth.uid(),
  unique(reconciliation_id,transaction_id)
);

create index idx_bank_reconciliations_club_account on public.bank_reconciliations(club_id,account_id,period_end desc);
create index idx_bank_reconciliation_items_recon on public.bank_reconciliation_items(reconciliation_id);

-- 5) Sessões de caixa.
create table public.cash_sessions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  account_id uuid not null references public.treasury_accounts(id) on delete restrict,
  book_opening_amount numeric(12,2) not null,
  opening_amount numeric(12,2) not null,
  opened_at timestamptz not null default now(),
  status text not null default 'open' check (status in ('open','pending_approval','closed')),
  expected_amount numeric(12,2),
  counted_amount numeric(12,2),
  difference_amount numeric(12,2),
  closing_notes text,
  closed_at timestamptz,
  closed_by uuid,
  approved_at timestamptz,
  approved_by uuid,
  created_at timestamptz default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz default now(),
  updated_by uuid default auth.uid()
);

create unique index uq_cash_sessions_active_account
  on public.cash_sessions(account_id)
  where status in ('open','pending_approval');
create index idx_cash_sessions_club_opened on public.cash_sessions(club_id,opened_at desc);

-- 6) Proteção contra referências cruzadas entre clubes.
create or replace function public.treasury_operational_reference_guard_v1()
returns trigger
language plpgsql
security invoker
set search_path='public'
as $$
declare
  v jsonb := to_jsonb(new);
  v_id uuid;
begin
  if nullif(v->>'account_id','') is not null then
    v_id := (v->>'account_id')::uuid;
    if not exists(select 1 from public.treasury_accounts a where a.id=v_id and a.club_id=new.club_id) then
      raise exception 'A conta financeira não pertence ao clube.';
    end if;
  end if;

  if nullif(v->>'cost_center_id','') is not null then
    v_id := (v->>'cost_center_id')::uuid;
    if not exists(select 1 from public.cost_centers c where c.id=v_id and c.club_id=new.club_id) then
      raise exception 'O centro de custo não pertence ao clube.';
    end if;
  end if;

  if nullif(v->>'event_id','') is not null then
    v_id := (v->>'event_id')::uuid;
    if not exists(select 1 from public.events e where e.id=v_id and e.club_id=new.club_id) then
      raise exception 'O evento não pertence ao clube.';
    end if;
  end if;

  if nullif(v->>'budget_id','') is not null then
    v_id := (v->>'budget_id')::uuid;
    if not exists(select 1 from public.budgets b where b.id=v_id and b.club_id=new.club_id) then
      raise exception 'O orçamento não pertence ao clube.';
    end if;
  end if;

  if nullif(v->>'reconciliation_id','') is not null then
    v_id := (v->>'reconciliation_id')::uuid;
    if not exists(select 1 from public.bank_reconciliations r where r.id=v_id and r.club_id=new.club_id) then
      raise exception 'A reconciliação não pertence ao clube.';
    end if;
  end if;

  if nullif(v->>'transaction_id','') is not null then
    v_id := (v->>'transaction_id')::uuid;
    if not exists(select 1 from public.treasury_transactions t where t.id=v_id and t.club_id=new.club_id) then
      raise exception 'O movimento não pertence ao clube.';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.treasury_operational_reference_guard_v1() from public,anon;
grant execute on function public.treasury_operational_reference_guard_v1() to authenticated;

-- 7) RLS e grants explícitos para Data API.
do $$
declare
  t text;
begin
  foreach t in array array[
    'payables','receivables','budgets','budget_lines',
    'bank_reconciliations','bank_reconciliation_items','cash_sessions'
  ]
  loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
    execute format('drop policy if exists treasury_operational_read on public.%I',t);
    execute format(
      'create policy treasury_operational_read on public.%I for select to authenticated using (public.has_club_permission(club_id,''viewTreasury''))',
      t
    );
  end loop;
end $$;

grant insert (club_id,counterparty,description,due_date,amount,account_id,cost_center_id,event_id,notes)
  on public.payables to authenticated;
grant update (counterparty,description,due_date,amount,account_id,cost_center_id,event_id,notes)
  on public.payables to authenticated;
grant insert (club_id,counterparty,description,due_date,amount,account_id,cost_center_id,event_id,notes)
  on public.receivables to authenticated;
grant update (counterparty,description,due_date,amount,account_id,cost_center_id,event_id,notes)
  on public.receivables to authenticated;

grant insert (club_id,name,period_start,period_end,notes) on public.budgets to authenticated;
grant update (name,period_start,period_end,notes) on public.budgets to authenticated;
grant insert (club_id,budget_id,label,line_type,planned_amount,cost_center_id,event_id,notes)
  on public.budget_lines to authenticated;
grant update (label,line_type,planned_amount,cost_center_id,event_id,notes)
  on public.budget_lines to authenticated;
grant delete on public.budget_lines to authenticated;

grant insert (club_id,account_id,period_start,period_end,statement_opening_balance,statement_closing_balance,notes)
  on public.bank_reconciliations to authenticated;
grant update (period_start,period_end,statement_opening_balance,statement_closing_balance,notes)
  on public.bank_reconciliations to authenticated;
grant insert (club_id,reconciliation_id,transaction_id) on public.bank_reconciliation_items to authenticated;
grant delete on public.bank_reconciliation_items to authenticated;

drop policy if exists payables_insert on public.payables;
create policy payables_insert on public.payables for insert to authenticated
with check (public.has_club_permission(club_id,'manageTreasuryPlanning'));
drop policy if exists payables_update on public.payables;
create policy payables_update on public.payables for update to authenticated
using (public.has_club_permission(club_id,'manageTreasuryPlanning') and status in ('open','partial'))
with check (public.has_club_permission(club_id,'manageTreasuryPlanning') and status in ('open','partial'));

drop policy if exists receivables_insert on public.receivables;
create policy receivables_insert on public.receivables for insert to authenticated
with check (public.has_club_permission(club_id,'manageTreasuryPlanning'));
drop policy if exists receivables_update on public.receivables;
create policy receivables_update on public.receivables for update to authenticated
using (public.has_club_permission(club_id,'manageTreasuryPlanning') and status in ('open','partial'))
with check (public.has_club_permission(club_id,'manageTreasuryPlanning') and status in ('open','partial'));

drop policy if exists budgets_insert on public.budgets;
create policy budgets_insert on public.budgets for insert to authenticated
with check (public.has_club_permission(club_id,'manageTreasuryPlanning'));
drop policy if exists budgets_update on public.budgets;
create policy budgets_update on public.budgets for update to authenticated
using (public.has_club_permission(club_id,'manageTreasuryPlanning') and status='draft')
with check (public.has_club_permission(club_id,'manageTreasuryPlanning') and status='draft');

drop policy if exists budget_lines_insert on public.budget_lines;
create policy budget_lines_insert on public.budget_lines for insert to authenticated
with check (
  public.has_club_permission(club_id,'manageTreasuryPlanning')
  and exists(select 1 from public.budgets b where b.id=budget_id and b.club_id=club_id and b.status='draft')
);
drop policy if exists budget_lines_update on public.budget_lines;
create policy budget_lines_update on public.budget_lines for update to authenticated
using (
  public.has_club_permission(club_id,'manageTreasuryPlanning')
  and exists(select 1 from public.budgets b where b.id=budget_id and b.club_id=club_id and b.status='draft')
)
with check (
  public.has_club_permission(club_id,'manageTreasuryPlanning')
  and exists(select 1 from public.budgets b where b.id=budget_id and b.club_id=club_id and b.status='draft')
);
drop policy if exists budget_lines_delete on public.budget_lines;
create policy budget_lines_delete on public.budget_lines for delete to authenticated
using (
  public.has_club_permission(club_id,'manageTreasuryPlanning')
  and exists(select 1 from public.budgets b where b.id=budget_id and b.club_id=club_id and b.status='draft')
);

drop policy if exists bank_reconciliations_insert on public.bank_reconciliations;
create policy bank_reconciliations_insert on public.bank_reconciliations for insert to authenticated
with check (public.has_club_permission(club_id,'manageTreasuryPlanning'));
drop policy if exists bank_reconciliations_update on public.bank_reconciliations;
create policy bank_reconciliations_update on public.bank_reconciliations for update to authenticated
using (public.has_club_permission(club_id,'manageTreasuryPlanning') and status='draft')
with check (public.has_club_permission(club_id,'manageTreasuryPlanning') and status='draft');

drop policy if exists bank_reconciliation_items_insert on public.bank_reconciliation_items;
create policy bank_reconciliation_items_insert on public.bank_reconciliation_items for insert to authenticated
with check (
  public.has_club_permission(club_id,'manageTreasuryPlanning')
  and exists(select 1 from public.bank_reconciliations r where r.id=reconciliation_id and r.club_id=club_id and r.status='draft')
);
drop policy if exists bank_reconciliation_items_delete on public.bank_reconciliation_items;
create policy bank_reconciliation_items_delete on public.bank_reconciliation_items for delete to authenticated
using (
  public.has_club_permission(club_id,'manageTreasuryPlanning')
  and exists(select 1 from public.bank_reconciliations r where r.id=reconciliation_id and r.club_id=club_id and r.status='draft')
);

-- 8) Audit global + validação de referências nos novos domínios.
do $$
declare
  t text;
begin
  foreach t in array array[
    'payables','receivables','budgets','budget_lines',
    'bank_reconciliations','bank_reconciliation_items','cash_sessions'
  ]
  loop
    execute format('drop trigger if exists trg_audit_stamp_v1 on public.%I',t);
    execute format('create trigger trg_audit_stamp_v1 before insert or update on public.%I for each row execute function public.audit_stamp_row_v1()',t);
    execute format('drop trigger if exists trg_treasury_operational_reference_guard_v1 on public.%I',t);
    execute format('create trigger trg_treasury_operational_reference_guard_v1 before insert or update on public.%I for each row execute function public.treasury_operational_reference_guard_v1()',t);
    execute format('drop trigger if exists trg_audit_capture_v1 on public.%I',t);
    execute format('create trigger trg_audit_capture_v1 after insert or update or delete on public.%I for each row execute function public.audit_capture_row_v1()',t);
  end loop;
end $$;

-- 9) Liquidação atómica de contas a pagar/receber.
create or replace function public.settle_treasury_obligation_v1(
  target_club uuid,
  p_obligation_type text,
  p_obligation uuid,
  p_account uuid,
  p_amount numeric,
  p_payment_method text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_row record;
  v_kind public.transaction_kind;
  v_transaction uuid;
  v_new_settled numeric;
  v_new_status text;
begin
  if auth.uid() is null
     or not public.has_club_permission(target_club,'manageTreasuryPlanning')
     or not public.has_club_permission(target_club,'createTreasuryMovement') then
    raise exception 'Sem permissão para liquidar obrigações financeiras.';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'O valor deve ser superior a zero.';
  end if;
  if not exists(select 1 from public.treasury_accounts a where a.id=p_account and a.club_id=target_club and a.active=true) then
    raise exception 'Conta financeira inválida.';
  end if;

  if p_obligation_type='payable' then
    select * into v_row from public.payables
    where id=p_obligation and club_id=target_club for update;
    v_kind := 'expense';
  elsif p_obligation_type='receivable' then
    select * into v_row from public.receivables
    where id=p_obligation and club_id=target_club for update;
    v_kind := 'income';
  else
    raise exception 'Tipo de obrigação inválido.';
  end if;

  if not found then raise exception 'Obrigação financeira não encontrada.'; end if;
  if v_row.status in ('paid','cancelled') then raise exception 'A obrigação já está encerrada.'; end if;
  if p_amount > (v_row.amount-v_row.settled_amount) then
    raise exception 'O valor excede o saldo da obrigação.';
  end if;

  insert into public.treasury_transactions(
    club_id,kind,account_id,transaction_date,description,amount,
    cost_center_id,event_id,payment_method,notes,source_type,source_id,created_by
  ) values (
    target_club,v_kind,p_account,current_date,
    case when p_obligation_type='payable' then 'Pagamento — ' else 'Recebimento — ' end || v_row.description,
    p_amount,v_row.cost_center_id,v_row.event_id,p_payment_method,p_notes,
    p_obligation_type,p_obligation,auth.uid()
  ) returning id into v_transaction;

  v_new_settled := v_row.settled_amount + p_amount;
  v_new_status := case when v_new_settled >= v_row.amount then 'paid' else 'partial' end;

  if p_obligation_type='payable' then
    update public.payables set settled_amount=v_new_settled,status=v_new_status,account_id=p_account where id=p_obligation;
  else
    update public.receivables set settled_amount=v_new_settled,status=v_new_status,account_id=p_account where id=p_obligation;
  end if;

  return v_transaction;
end;
$$;

-- 10) Cancelamento sem delete.
create or replace function public.cancel_treasury_obligation_v1(
  target_club uuid,
  p_obligation_type text,
  p_obligation uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_settled numeric;
  v_status text;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageTreasuryPlanning') then
    raise exception 'Sem permissão para cancelar obrigações financeiras.';
  end if;
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'Indica o motivo do cancelamento.'; end if;

  if p_obligation_type='payable' then
    select settled_amount,status into v_settled,v_status from public.payables
      where id=p_obligation and club_id=target_club for update;
    if not found then raise exception 'Conta a pagar não encontrada.'; end if;
    if v_settled > 0 then raise exception 'Uma obrigação com liquidações não pode ser cancelada.'; end if;
    if v_status='cancelled' then return; end if;
    update public.payables
      set status='cancelled',cancelled_at=now(),cancelled_by=auth.uid(),
          notes=concat_ws(E'\n',notes,'Cancelado: '||trim(p_reason))
      where id=p_obligation;
  elsif p_obligation_type='receivable' then
    select settled_amount,status into v_settled,v_status from public.receivables
      where id=p_obligation and club_id=target_club for update;
    if not found then raise exception 'Conta a receber não encontrada.'; end if;
    if v_settled > 0 then raise exception 'Uma obrigação com liquidações não pode ser cancelada.'; end if;
    if v_status='cancelled' then return; end if;
    update public.receivables
      set status='cancelled',cancelled_at=now(),cancelled_by=auth.uid(),
          notes=concat_ws(E'\n',notes,'Cancelado: '||trim(p_reason))
      where id=p_obligation;
  else
    raise exception 'Tipo de obrigação inválido.';
  end if;
end;
$$;

-- 11) Aprovar/fechar orçamento e desempenho realizado.
create or replace function public.set_budget_status_v1(
  target_club uuid,
  p_budget uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_current text;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageTreasuryPlanning') then
    raise exception 'Sem permissão para gerir orçamentos.';
  end if;
  select status into v_current from public.budgets where id=p_budget and club_id=target_club for update;
  if not found then raise exception 'Orçamento não encontrado.'; end if;

  if p_status='approved' and v_current='draft' then
    update public.budgets set status='approved',approved_at=now(),approved_by=auth.uid() where id=p_budget;
  elsif p_status='closed' and v_current='approved' then
    update public.budgets set status='closed',closed_at=now(),closed_by=auth.uid() where id=p_budget;
  else
    raise exception 'Transição de estado do orçamento inválida.';
  end if;
end;
$$;

create or replace function public.budget_performance_v1(target_club uuid,p_budget uuid)
returns table(
  line_id uuid,
  label text,
  line_type text,
  planned_amount numeric,
  actual_amount numeric,
  variance_amount numeric,
  cost_center_id uuid,
  event_id uuid
)
language plpgsql
stable
security definer
set search_path='public'
as $$
declare
  v_budget public.budgets%rowtype;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'viewTreasury') then
    raise exception 'Sem acesso à tesouraria.';
  end if;
  select * into v_budget from public.budgets where id=p_budget and club_id=target_club;
  if not found then raise exception 'Orçamento não encontrado.'; end if;

  return query
  select
    l.id,
    l.label,
    l.line_type,
    l.planned_amount,
    coalesce(sum(t.amount) filter (
      where t.id is not null
        and t.reversal_of is null
        and not exists(select 1 from public.treasury_transactions r where r.reversal_of=t.id)
    ),0)::numeric as actual_amount,
    (coalesce(sum(t.amount) filter (
      where t.id is not null
        and t.reversal_of is null
        and not exists(select 1 from public.treasury_transactions r where r.reversal_of=t.id)
    ),0)-l.planned_amount)::numeric as variance_amount,
    l.cost_center_id,
    l.event_id
  from public.budget_lines l
  left join public.treasury_transactions t
    on t.club_id=l.club_id
   and t.transaction_date between v_budget.period_start and v_budget.period_end
   and t.kind::text=l.line_type
   and (l.cost_center_id is null or t.cost_center_id=l.cost_center_id)
   and (l.event_id is null or t.event_id=l.event_id)
  where l.club_id=target_club and l.budget_id=p_budget
  group by l.id,l.label,l.line_type,l.planned_amount,l.cost_center_id,l.event_id,l.created_at
  order by l.created_at,l.label;
end;
$$;

-- 12) Fecho de reconciliação.
create or replace function public.close_bank_reconciliation_v1(target_club uuid,p_reconciliation uuid)
returns numeric
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_rec public.bank_reconciliations%rowtype;
  v_book numeric;
  v_difference numeric;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageTreasuryPlanning') then
    raise exception 'Sem permissão para fechar reconciliações.';
  end if;
  select * into v_rec from public.bank_reconciliations
    where id=p_reconciliation and club_id=target_club for update;
  if not found then raise exception 'Reconciliação não encontrada.'; end if;
  if v_rec.status<>'draft' then raise exception 'A reconciliação já está fechada.'; end if;

  select a.opening_balance + coalesce(sum(
    case
      when t.kind='income' and t.account_id=a.id then t.amount
      when t.kind='expense' and t.account_id=a.id then -t.amount
      when t.kind='transfer' and t.account_id=a.id then -t.amount
      when t.kind='transfer' and t.destination_account_id=a.id then t.amount
      else 0
    end
  ),0)
  into v_book
  from public.treasury_accounts a
  left join public.treasury_transactions t
    on t.club_id=a.club_id
   and t.transaction_date<=v_rec.period_end
   and (t.account_id=a.id or t.destination_account_id=a.id)
  where a.id=v_rec.account_id and a.club_id=target_club
  group by a.id,a.opening_balance;

  v_difference := v_rec.statement_closing_balance-coalesce(v_book,0);
  update public.bank_reconciliations
    set book_closing_balance=coalesce(v_book,0),difference_amount=v_difference,
        status='closed',closed_at=now(),closed_by=auth.uid()
    where id=p_reconciliation;
  return v_difference;
end;
$$;

-- 13) Abertura, fecho e aprovação de caixa.
create or replace function public.open_cash_session_v1(
  target_club uuid,
  p_account uuid,
  p_opening_amount numeric
)
returns uuid
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_id uuid;
  v_book numeric;
  v_type text;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageCashSessions') then
    raise exception 'Sem permissão para abrir caixa.';
  end if;
  if p_opening_amount is null then raise exception 'Indica o valor contado na abertura.'; end if;
  select account_type into v_type from public.treasury_accounts
    where id=p_account and club_id=target_club and active=true;
  if not found then raise exception 'Conta de caixa inválida.'; end if;
  if v_type<>'cash' then raise exception 'A sessão de caixa só pode usar uma conta do tipo Caixa / Dinheiro.'; end if;
  if exists(select 1 from public.cash_sessions where account_id=p_account and status in ('open','pending_approval')) then
    raise exception 'Já existe uma sessão ativa para esta caixa.';
  end if;
  v_book := public.treasury_account_balance_v1(p_account);
  insert into public.cash_sessions(club_id,account_id,book_opening_amount,opening_amount,created_by)
  values(target_club,p_account,coalesce(v_book,0),p_opening_amount,auth.uid()) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.close_cash_session_v1(
  target_club uuid,
  p_session uuid,
  p_counted_amount numeric,
  p_notes text default null
)
returns text
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_session public.cash_sessions%rowtype;
  v_expected numeric;
  v_difference numeric;
  v_status text;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageCashSessions') then
    raise exception 'Sem permissão para fechar caixa.';
  end if;
  if p_counted_amount is null then raise exception 'Indica o valor contado no fecho.'; end if;
  select * into v_session from public.cash_sessions
    where id=p_session and club_id=target_club for update;
  if not found then raise exception 'Sessão de caixa não encontrada.'; end if;
  if v_session.status<>'open' then raise exception 'A sessão já não está aberta.'; end if;

  v_expected := public.treasury_account_balance_v1(v_session.account_id);
  v_difference := p_counted_amount-coalesce(v_expected,0);
  v_status := case when abs(v_difference)<0.005 then 'closed' else 'pending_approval' end;

  update public.cash_sessions
    set expected_amount=coalesce(v_expected,0),counted_amount=p_counted_amount,
        difference_amount=v_difference,closing_notes=p_notes,status=v_status,
        closed_at=now(),closed_by=auth.uid()
    where id=p_session;
  return v_status;
end;
$$;

create or replace function public.approve_cash_session_v1(
  target_club uuid,
  p_session uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_session public.cash_sessions%rowtype;
  v_transaction uuid;
  v_kind public.transaction_kind;
  v_amount numeric;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'approveCashDifferences') then
    raise exception 'Sem permissão para aprovar diferenças de caixa.';
  end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Indica o motivo da aprovação.'; end if;
  select * into v_session from public.cash_sessions
    where id=p_session and club_id=target_club for update;
  if not found then raise exception 'Sessão de caixa não encontrada.'; end if;
  if v_session.status<>'pending_approval' then raise exception 'A sessão não aguarda aprovação.'; end if;

  v_amount := abs(coalesce(v_session.difference_amount,0));
  if v_amount<0.005 then raise exception 'A sessão não tem diferença a regularizar.'; end if;
  v_kind := case when v_session.difference_amount>0 then 'income'::public.transaction_kind else 'expense'::public.transaction_kind end;

  insert into public.treasury_transactions(
    club_id,kind,account_id,transaction_date,description,amount,payment_method,
    notes,source_type,source_id,created_by
  ) values (
    target_club,v_kind,v_session.account_id,current_date,
    'Ajuste de caixa — sessão '||p_session::text,v_amount,'Dinheiro',trim(p_reason),
    'cash_session',p_session,auth.uid()
  ) returning id into v_transaction;

  update public.cash_sessions
    set status='closed',approved_at=now(),approved_by=auth.uid(),
        closing_notes=concat_ws(E'\n',closing_notes,'Aprovação: '||trim(p_reason))
    where id=p_session;
  return v_transaction;
end;
$$;

-- 14) Reversão segura de movimento, sem apagar histórico.
create or replace function public.reverse_treasury_transaction_v1(
  target_club uuid,
  p_transaction uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_original public.treasury_transactions%rowtype;
  v_id uuid;
  v_kind public.transaction_kind;
  v_account uuid;
  v_destination uuid;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'reverseTreasuryMovement') then
    raise exception 'Sem permissão para reverter movimentos.';
  end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Indica o motivo da reversão.'; end if;

  select * into v_original from public.treasury_transactions
    where id=p_transaction and club_id=target_club for update;
  if not found then raise exception 'Movimento não encontrado.'; end if;
  if v_original.reversal_of is not null or v_original.kind='reversal' then
    raise exception 'Um movimento de reversão não pode ser revertido por este fluxo.';
  end if;
  if exists(select 1 from public.treasury_transactions r where r.reversal_of=p_transaction) then
    raise exception 'O movimento já foi revertido.';
  end if;
  if v_original.source_type is not null and v_original.source_type not in ('payable','receivable') then
    raise exception 'Este movimento pertence a outro módulo e deve ser corrigido na origem.';
  end if;

  if v_original.kind='income' then
    v_kind:='expense'; v_account:=v_original.account_id; v_destination:=null;
  elsif v_original.kind='expense' then
    v_kind:='income'; v_account:=v_original.account_id; v_destination:=null;
  elsif v_original.kind='transfer' then
    v_kind:='transfer'; v_account:=v_original.destination_account_id; v_destination:=v_original.account_id;
  else
    raise exception 'Tipo de movimento não reversível.';
  end if;

  insert into public.treasury_transactions(
    club_id,kind,account_id,destination_account_id,category_id,cost_center_id,event_id,
    transaction_date,description,amount,payment_method,notes,source_type,source_id,
    reversal_of,created_by
  ) values (
    target_club,v_kind,v_account,v_destination,v_original.category_id,v_original.cost_center_id,
    v_original.event_id,current_date,'Reversão — '||v_original.description,v_original.amount,
    v_original.payment_method,trim(p_reason),'reversal',p_transaction,p_transaction,auth.uid()
  ) returning id into v_id;

  if v_original.source_type='payable' and v_original.source_id is not null then
    update public.payables
      set settled_amount=greatest(0,settled_amount-v_original.amount),
          status=case
            when greatest(0,settled_amount-v_original.amount)=0 then 'open'
            when greatest(0,settled_amount-v_original.amount)<amount then 'partial'
            else 'paid'
          end
      where id=v_original.source_id and club_id=target_club;
  elsif v_original.source_type='receivable' and v_original.source_id is not null then
    update public.receivables
      set settled_amount=greatest(0,settled_amount-v_original.amount),
          status=case
            when greatest(0,settled_amount-v_original.amount)=0 then 'open'
            when greatest(0,settled_amount-v_original.amount)<amount then 'partial'
            else 'paid'
          end
      where id=v_original.source_id and club_id=target_club;
  end if;

  return v_id;
end;
$$;

-- 15) Centros de custo por RPC para manter autorização coerente.
create or replace function public.save_cost_center_v1(
  target_club uuid,
  p_id uuid,
  p_name text,
  p_code text default null,
  p_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageTreasuryPlanning') then
    raise exception 'Sem permissão para gerir centros de custo.';
  end if;
  if length(trim(coalesce(p_name,'')))<2 then raise exception 'Indica o nome do centro de custo.'; end if;

  if p_id is null then
    insert into public.cost_centers(club_id,name,code,active,created_by)
    values(target_club,trim(p_name),nullif(trim(coalesce(p_code,'')),''),coalesce(p_active,true),auth.uid())
    returning id into v_id;
  else
    update public.cost_centers
      set name=trim(p_name),code=nullif(trim(coalesce(p_code,'')),''),active=coalesce(p_active,true)
      where id=p_id and club_id=target_club
      returning id into v_id;
    if v_id is null then raise exception 'Centro de custo não encontrado.'; end if;
  end if;
  return v_id;
end;
$$;

-- 16) Segurança de RPCs: nunca PUBLIC/anon.
do $$
declare
  sig text;
begin
  foreach sig in array array[
    'public.settle_treasury_obligation_v1(uuid,text,uuid,uuid,numeric,text,text)',
    'public.cancel_treasury_obligation_v1(uuid,text,uuid,text)',
    'public.set_budget_status_v1(uuid,uuid,text)',
    'public.budget_performance_v1(uuid,uuid)',
    'public.close_bank_reconciliation_v1(uuid,uuid)',
    'public.open_cash_session_v1(uuid,uuid,numeric)',
    'public.close_cash_session_v1(uuid,uuid,numeric,text)',
    'public.approve_cash_session_v1(uuid,uuid,text)',
    'public.reverse_treasury_transaction_v1(uuid,uuid,text)',
    'public.save_cost_center_v1(uuid,uuid,text,text,boolean)'
  ]
  loop
    execute format('revoke all on function %s from public, anon',sig);
    execute format('grant execute on function %s to authenticated',sig);
  end loop;
end $$;
