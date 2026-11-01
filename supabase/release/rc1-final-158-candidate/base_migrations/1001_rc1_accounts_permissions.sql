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

-- Staging replay only: account_balance omitted; absent in captured production.


-- Staging replay only: transfer_between_accounts omitted; absent in captured production.


-- A tabela funds é mantida apenas para compatibilidade histórica nesta migração.
-- A aplicação RC1 deixa de a consultar ou apresentar.
