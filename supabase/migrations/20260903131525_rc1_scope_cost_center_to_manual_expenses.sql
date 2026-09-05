alter table public.treasury_transactions
  drop constraint if exists treasury_transactions_expense_cost_center_check;
