-- Read-only regression assertions for the security-definer API grants.
begin;
do $$
declare
  trigger_count integer;
begin
  if has_function_privilege('anon','public.enforce_event_capacity_floor_v1()','EXECUTE')
    or has_function_privilege('anon','public.enforce_event_capacity_seat_v1()','EXECUTE') then
    raise exception 'anon can execute an event capacity trigger function';
  end if;

  if has_function_privilege('authenticated','public.enforce_event_capacity_floor_v1()','EXECUTE')
    or has_function_privilege('authenticated','public.enforce_event_capacity_seat_v1()','EXECUTE') then
    raise exception 'authenticated can directly execute an event capacity trigger function';
  end if;

  if not has_function_privilege('authenticated','public.register_euromillions_month_fine_payment_v1(uuid,uuid,integer,integer,text)','EXECUTE')
    or not has_function_privilege('authenticated','public.reverse_euromillions_draw_payment_v1(uuid,uuid,text)','EXECUTE')
    or not has_function_privilege('authenticated','public.reverse_euromillions_fine_payment_v1(uuid,uuid,text)','EXECUTE')
    or not has_function_privilege('authenticated','public.reverse_euromillions_month_payment_v1(uuid,uuid,integer,integer,text)','EXECUTE')
    or not has_function_privilege('authenticated','public.reverse_euromillions_prize_receipt_v1(uuid,uuid,text)','EXECUTE') then
    raise exception 'authenticated is missing EXECUTE on an Euromillions RPC';
  end if;

  if has_function_privilege('anon','public.register_euromillions_month_fine_payment_v1(uuid,uuid,integer,integer,text)','EXECUTE')
    or has_function_privilege('anon','public.reverse_euromillions_draw_payment_v1(uuid,uuid,text)','EXECUTE')
    or has_function_privilege('anon','public.reverse_euromillions_fine_payment_v1(uuid,uuid,text)','EXECUTE')
    or has_function_privilege('anon','public.reverse_euromillions_month_payment_v1(uuid,uuid,integer,integer,text)','EXECUTE')
    or has_function_privilege('anon','public.reverse_euromillions_prize_receipt_v1(uuid,uuid,text)','EXECUTE') then
    raise exception 'anon can execute an Euromillions RPC';
  end if;

  select count(*) into trigger_count
  from (values
    ('trg_event_registrations_capacity','event_registrations','enforce_event_capacity_seat_v1'),
    ('trg_event_registration_guests_capacity','event_registration_guests','enforce_event_capacity_seat_v1'),
    ('trg_events_capacity_floor','events','enforce_event_capacity_floor_v1')
  ) expected(trigger_name,table_name,function_name)
  where exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    join pg_proc p on p.oid=t.tgfoid
    where not t.tgisinternal
      and n.nspname='public'
      and t.tgname=expected.trigger_name
      and c.relname=expected.table_name
      and p.proname=expected.function_name
  );
  if trigger_count<>3 then
    raise exception 'Expected all three event capacity triggers bound to their functions; found %',trigger_count;
  end if;

  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.prosecdef
      and has_function_privilege('anon',p.oid,'EXECUTE')
  ) then
    raise exception 'A SECURITY DEFINER function in public remains executable by anon';
  end if;
end;
$$;
rollback;
select 'security_definer_execute_hardening: all assertions passed' as result;
