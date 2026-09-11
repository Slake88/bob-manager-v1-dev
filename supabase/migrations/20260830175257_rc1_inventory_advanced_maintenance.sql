create extension if not exists pg_cron;

create or replace function public.inventory_advanced_maintenance_v1()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_reservations integer; v_lots integer;
begin
  v_reservations:=public.inventory_expire_reservations_internal_v1(null);
  v_lots:=public.inventory_refresh_lot_status_internal_v1(null);
  return jsonb_build_object('expired_reservations',v_reservations,'updated_lots',v_lots,'ran_at',now());
end $$;
revoke all on function public.inventory_advanced_maintenance_v1() from public,anon,authenticated;

select cron.schedule('bob-inventory-advanced-hourly','5 * * * *',$$select public.inventory_advanced_maintenance_v1();$$);