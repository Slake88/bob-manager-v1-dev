insert into public.club_settings (club_id, key, value)
select p.club_id, 'dinner_fee_amount', to_char(p.unit_price, 'FM999999990.00')
from public.bar_sale_presets p
where lower(p.name) = lower('Jantar')
on conflict (club_id, key) do nothing;

create or replace function public.sync_dinner_fee_setting_v1()
returns trigger
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_amount numeric;
begin
  if new.key <> 'dinner_fee_amount' then
    return new;
  end if;

  begin
    v_amount := replace(btrim(new.value), ',', '.')::numeric;
  exception when others then
    raise exception 'O valor do jantar tem de ser numérico.';
  end;

  if v_amount <= 0 then
    raise exception 'O valor do jantar tem de ser superior a zero.';
  end if;

  update public.bar_sale_presets
  set unit_price = v_amount,
      updated_by = coalesce(new.updated_by, auth.uid()),
      updated_at = now()
  where club_id = new.club_id
    and lower(name) = lower('Jantar');

  return new;
end;
$$;

revoke all on function public.sync_dinner_fee_setting_v1() from public, anon, authenticated;
grant execute on function public.sync_dinner_fee_setting_v1() to service_role;

drop trigger if exists trg_sync_dinner_fee_setting on public.club_settings;
create trigger trg_sync_dinner_fee_setting
after insert or update of value on public.club_settings
for each row
when (new.key = 'dinner_fee_amount')
execute function public.sync_dinner_fee_setting_v1();

update public.bar_sale_presets p
set unit_price = replace(btrim(s.value), ',', '.')::numeric,
    updated_at = now()
from public.club_settings s
where s.club_id = p.club_id
  and s.key = 'dinner_fee_amount'
  and lower(p.name) = lower('Jantar')
  and btrim(s.value) ~ '^[0-9]+([,.][0-9]+)?$';