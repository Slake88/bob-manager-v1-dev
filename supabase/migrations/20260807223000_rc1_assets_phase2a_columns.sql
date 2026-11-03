alter table public.asset_loans add column if not exists returned_condition text;
alter table public.asset_loans add column if not exists return_notes text;
alter table public.asset_loans add column if not exists updated_at timestamptz not null default now();
alter table public.asset_maintenance add column if not exists account_id uuid references public.treasury_accounts(id) on delete set null;
alter table public.asset_maintenance add column if not exists payment_method text;
alter table public.asset_maintenance add column if not exists treasury_transaction_id uuid references public.treasury_transactions(id) on delete set null;
