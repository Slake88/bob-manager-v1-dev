-- Prepared only: never executed against production in this phase.
-- Metadata and aggregate contract checks; no business RPC, DDL or row exports.
begin transaction read only;
select schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check
from pg_policies where schemaname='public' order by tablename,policyname;
select c.relname,r.rolname,
 has_table_privilege(r.rolname,c.oid,'SELECT') can_select,
 has_table_privilege(r.rolname,c.oid,'INSERT') can_insert,
 has_table_privilege(r.rolname,c.oid,'UPDATE') can_update,
 has_table_privilege(r.rolname,c.oid,'DELETE') can_delete
from pg_class c join pg_namespace n on n.oid=c.relnamespace
cross join pg_roles r where n.nspname='public' and c.relkind in ('r','p')
and r.rolname in ('anon','authenticated','service_role') order by c.relname,r.rolname;
select table_name,column_name,data_type,udt_name,is_nullable,column_default
from information_schema.columns where table_schema='public'
and table_name in ('products','product_variants','stock_movements','stock_lots','stock_reservations','inventory_stock_balances','fee_obligations','fee_payments','fee_payment_allocations','notifications')
order by table_name,ordinal_position;
select conrelid::regclass relation,conname,contype,convalidated,pg_get_constraintdef(oid) definition
from pg_constraint where connamespace='public'::regnamespace
and conrelid in ('public.products'::regclass,'public.product_variants'::regclass,'public.stock_movements'::regclass,'public.stock_lots'::regclass,'public.stock_reservations'::regclass,'public.fee_obligations'::regclass,'public.fee_payments'::regclass,'public.fee_payment_allocations'::regclass)
order by conrelid::regclass::text,conname;
select c.relname,c.reloptions from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='v' order by c.relname;
select count(*) invalid_balances from public.inventory_stock_balances
where quantity<0 or reserved_quantity<0 or reserved_quantity>quantity;
select count(*) invalid_lots from public.stock_lots
where initial_quantity<=0 or quantity<0 or quantity>initial_quantity;
select count(*) invalid_reservation_periods from public.stock_reservations
where expires_at<=reserved_at or expires_at>reserved_at+interval '30 days';
select count(*) duplicate_obligation_groups from (
 select club_id,member_id,reference_year,reference_month from public.fee_obligations
 where reference_month is not null group by 1,2,3,4 having count(*)>1
) s;
select count(*) duplicate_allocation_groups from (
 select payment_id,obligation_id from public.fee_payment_allocations
 group by 1,2 having count(*)>1
) s;
rollback;
