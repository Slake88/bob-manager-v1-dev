alter table public.fee_obligations
  add column if not exists exempt_amount numeric(12,2) not null default 0,
  add column if not exists adjustment_amount numeric(12,2) not null default 0;

alter table public.fee_payments
  add column if not exists member_id uuid references public.members(id),
  add column if not exists payment_method text,
  add column if not exists payment_date date,
  add column if not exists status text not null default 'confirmed',
  add column if not exists reversed_at timestamptz,
  add column if not exists reversed_by uuid,
  add column if not exists reversal_reason text;

update public.fee_payments fp
set member_id=o.member_id
from public.fee_obligations o
where fp.member_id is null and o.id=fp.obligation_id;

update public.fee_payments fp
set payment_method=t.payment_method,
    payment_date=coalesce(fp.payment_date,fp.paid_at::date)
from public.treasury_transactions t
where t.id=fp.transaction_id
  and (fp.payment_method is null or fp.payment_date is null);

update public.fee_payments
set payment_date=coalesce(payment_date,paid_at::date,current_date)
where payment_date is null;

alter table public.fee_payments
  alter column member_id set not null,
  alter column obligation_id drop not null;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conname='fee_payments_status_check'
      and conrelid='public.fee_payments'::regclass
  ) then
    alter table public.fee_payments add constraint fee_payments_status_check
      check(status in ('confirmed','reversed'));
  end if;
end $$;

create table if not exists public.fee_payment_allocations(
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  payment_id uuid not null references public.fee_payments(id) on delete restrict,
  obligation_id uuid not null references public.fee_obligations(id) on delete restrict,
  amount numeric(12,2) not null check(amount>0),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  unique(payment_id,obligation_id)
);

insert into public.fee_payment_allocations(club_id,payment_id,obligation_id,amount,created_at,created_by)
select fp.club_id,fp.id,fp.obligation_id,fp.amount,coalesce(fp.created_at,fp.paid_at,now()),fp.created_by
from public.fee_payments fp
where fp.obligation_id is not null
on conflict(payment_id,obligation_id) do nothing;

create table if not exists public.fee_credits(
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete restrict,
  amount numeric(12,2) not null check(amount<>0),
  entry_type text not null check(entry_type in ('payment_excess','manual_adjustment','application','reversal')),
  payment_id uuid references public.fee_payments(id) on delete restrict,
  obligation_id uuid references public.fee_obligations(id) on delete restrict,
  source_credit_id uuid references public.fee_credits(id) on delete restrict,
  reversal_of uuid references public.fee_credits(id) on delete restrict,
  reason text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

create table if not exists public.fee_exemptions(
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete restrict,
  obligation_id uuid not null references public.fee_obligations(id) on delete restrict,
  amount numeric(12,2) not null check(amount>0),
  reason text not null,
  status text not null default 'active' check(status in ('active','reversed')),
  reversed_at timestamptz,
  reversed_by uuid,
  reversal_reason text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

create table if not exists public.fee_adjustments(
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete restrict,
  obligation_id uuid not null references public.fee_obligations(id) on delete restrict,
  amount numeric(12,2) not null check(amount<>0),
  reason text not null,
  status text not null default 'active' check(status in ('active','reversed')),
  reversed_at timestamptz,
  reversed_by uuid,
  reversal_reason text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

create table if not exists public.reported_payments(
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete restrict,
  amount numeric(12,2) not null check(amount>0),
  paid_on date not null,
  payment_method text not null,
  notes text,
  proof_path text not null,
  proof_name text not null,
  proof_mime_type text,
  proof_size bigint check(proof_size is null or proof_size>=0),
  status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled','reversed')),
  review_notes text,
  reviewed_at timestamptz,
  reviewed_by uuid,
  fee_payment_id uuid references public.fee_payments(id) on delete restrict,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

create index if not exists fee_payment_allocations_lookup_idx on public.fee_payment_allocations(club_id,payment_id,obligation_id);
create index if not exists fee_credits_member_idx on public.fee_credits(club_id,member_id,created_at);
create index if not exists fee_credits_source_idx on public.fee_credits(source_credit_id) where source_credit_id is not null;
create unique index if not exists fee_credits_reversal_once_idx on public.fee_credits(reversal_of) where reversal_of is not null;
create index if not exists fee_exemptions_member_idx on public.fee_exemptions(club_id,member_id,obligation_id);
create index if not exists fee_adjustments_member_idx on public.fee_adjustments(club_id,member_id,obligation_id);
create index if not exists reported_payments_review_idx on public.reported_payments(club_id,status,created_at desc);
create index if not exists fee_payments_member_idx on public.fee_payments(club_id,member_id,payment_date desc);