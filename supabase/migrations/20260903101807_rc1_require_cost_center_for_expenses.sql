alter table public.treasury_transactions
  add constraint treasury_transactions_expense_cost_center_check
  check (kind <> 'expense' or cost_center_id is not null)
  not valid;
