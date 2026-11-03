begin;
-- Phase 2C.3: schema/code only. No preparation, backfill or data changes.
create schema if not exists bob_lottery_private;
revoke all on schema bob_lottery_private from public, anon, authenticated, service_role;

-- Called only by guarded SECURITY DEFINER entry points; no external grants.
create or replace function bob_lottery_private.prepare_month(
  target_club uuid, p_year integer, p_month integer
) returns void language plpgsql volatile security invoker
set search_path = pg_catalog, public, pg_temp as $$
declare
  v_amount numeric;
  d date;
  v_first date;
begin
  if auth.uid() is null or not public.has_club_access(target_club)
     or not public.has_club_permission(target_club, 'manageLottery') then
    raise exception 'Sem permissão para preparar o mês.' using errcode='42501';
  end if;
  if p_year is null or p_year < 1 or p_year > 9999
     or p_month is null or p_month < 1 or p_month > 12 then
    raise exception 'Mês inválido.' using errcode='22023';
  end if;
  v_first := make_date(p_year, p_month, 1);
  if v_first < date_trunc('month', now() at time zone 'Europe/Lisbon')::date then
    raise exception 'Meses passados apenas mostram o histórico existente; não podem gerar novas cobranças.' using errcode='22023';
  end if;
  select coalesce((select value::numeric from public.club_settings
    where club_id=target_club and key='euromillions_draw_amount'), 2.20) into v_amount;
  d := v_first;
  while extract(month from d)=p_month loop
    if extract(isodow from d) in (2,5) then
      insert into public.euromillions_draw_charges
        (club_id,player_id,week_start,draw_date,amount)
      select target_club,p.id,d-(extract(isodow from d)::integer-1),d,v_amount
      from public.euromillions_players p
      where p.club_id=target_club and p.status='active'
      on conflict (club_id,player_id,draw_date) do nothing;
    end if;
    d := d+1;
  end loop;
end;
$$;
revoke all on function bob_lottery_private.prepare_month(uuid,integer,integer)
  from public, anon, authenticated, service_role;

create or replace function public.prepare_euromillions_month_v1(
  target_club uuid, p_year integer, p_month integer
) returns void language plpgsql volatile security definer
set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null or not public.has_club_access(target_club)
     or not public.has_club_permission(target_club, 'manageLottery') then
    raise exception 'Sem permissão para preparar o mês.' using errcode='42501';
  end if;
  perform bob_lottery_private.prepare_month(target_club,p_year,p_month);
end;
$$;
revoke all on function public.prepare_euromillions_month_v1(uuid,integer,integer)
  from public, anon, authenticated, service_role;
grant execute on function public.prepare_euromillions_month_v1(uuid,integer,integer) to authenticated;

-- Preserve the old SQL signature for compatibility, with no external execute.
create or replace function public.generate_euromillions_charges_v1(
  target_club uuid, p_year integer, p_month integer
) returns void language plpgsql volatile security invoker
set search_path = pg_catalog, public, pg_temp as $$
begin
  perform bob_lottery_private.prepare_month(target_club,p_year,p_month);
end;
$$;
revoke all on function public.generate_euromillions_charges_v1(uuid,integer,integer)
  from public, anon, authenticated, service_role;
-- No application/SQL caller needs the global sync any more. Retain its signature
-- for compatibility, but retire the write and remove SECURITY DEFINER/exposure.
create or replace function public.sync_euromillions_players_v1(target_club uuid)
returns void language plpgsql volatile security invoker
set search_path = pg_catalog, public, pg_temp as $$
begin
  raise exception 'Sincronização global desativada; configure apenas o membro escolhido.';
end;
$$;
revoke all on function public.sync_euromillions_players_v1(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.register_euromillions_month_payment_v1(
  target_club uuid,p_player uuid,p_year integer,p_month integer,p_payment_method text default null
) returns void language plpgsql volatile security definer
set search_path = pg_catalog, public, pg_temp as $$
declare r record; v_first date; v_next date;
begin
  if auth.uid() is null or not public.has_club_access(target_club)
     or not public.has_club_permission(target_club,'manageLottery') then
    raise exception 'Sem permissão para registar pagamentos.' using errcode='42501';
  end if;
  if p_year is null or p_year < 1 or p_year > 9999
     or p_month is null or p_month < 1 or p_month > 12 then
    raise exception 'Mês inválido.' using errcode='22023';
  end if;
  if not exists(select 1 from public.euromillions_players
                where id=p_player and club_id=target_club) then
    raise exception 'Jogador não encontrado.' using errcode='22023';
  end if;
  v_first := make_date(p_year,p_month,1);
  v_next := (v_first + interval '1 month')::date;
  if v_first >= date_trunc('month',now() at time zone 'Europe/Lisbon')::date then
    perform bob_lottery_private.prepare_month(target_club,p_year,p_month);
  elsif not exists(select 1 from public.euromillions_draw_charges
    where club_id=target_club and player_id=p_player and draw_date>=v_first and draw_date<v_next) then
    raise exception 'Não existem cobranças históricas para este jogador neste mês; o histórico não será reconstruído.' using errcode='22023';
  end if;
  for r in select id from public.euromillions_draw_charges
    where club_id=target_club and player_id=p_player
      and draw_date>=v_first and draw_date<v_next and paid_amount<amount
    order by draw_date loop
    perform public.register_euromillions_draw_payment_v1(target_club,r.id,p_payment_method);
  end loop;
end;
$$;
revoke all on function public.register_euromillions_month_payment_v1(uuid,uuid,integer,integer,text)
  from public, anon, authenticated, service_role;
grant execute on function public.register_euromillions_month_payment_v1(uuid,uuid,integer,integer,text) to authenticated;

-- Selected-member upserts remain SECURITY INVOKER through the table's RLS.
-- Reject cross-club member references on INSERT/UPDATE as well as denying viewers.
alter policy euromillions_players_manage on public.euromillions_players
  with check (public.has_club_permission(club_id,'manageLottery') and exists (
    select 1 from public.members m
    where m.id=euromillions_players.member_id and m.club_id=euromillions_players.club_id
  ));

-- Approved temporal guard; retain Phase 2A authorization and service-role import.
create or replace function public.process_euromillions_official_result_v1(
  target_club uuid,
  p_draw_date date,
  p_draw_number text,
  p_numbers integer[],
  p_stars integer[],
  p_prizes jsonb default '{}'::jsonb,
  p_source text default 'official'
)
returns uuid language plpgsql security definer set search_path=pg_catalog, public as $$
declare
  rid uuid;
  fine_unit numeric;
  p record;
  hit_n int;
  hit_s int;
  miss_n int;
  miss_s int;
  cat int;
  prize numeric;
  prize_entry record;
begin
  if auth.role() = 'service_role' then
    if p_source is null or lower(p_source) = 'manual' then
      raise exception 'Importação oficial inválida.';
    end if;
  elsif auth.role() = 'authenticated' and auth.uid() is not null then
    if not exists (
      select 1
      from public.club_memberships cm
      where cm.club_id = target_club
        and cm.profile_id = auth.uid()
        and cm.active is true
    ) then
      raise exception 'Sem acesso ao clube.' using errcode = '42501';
    end if;
    if not exists (
      select 1
      from public.club_memberships cm
      where cm.club_id = target_club
        and cm.profile_id = auth.uid()
        and cm.active is true
        and lower(cm.access_role) in ('treasurer', 'super_admin', 'super admin')
    ) then
      raise exception 'Sem permissão para processar resultados.' using errcode = '42501';
    end if;
    if p_source is distinct from 'manual'
      or p_draw_number is not null
      or p_prizes is distinct from '{}'::jsonb then
      raise exception 'O processamento manual exige origem manual e não aceita número ou prémios oficiais.';
    end if;
  else
    raise exception 'Autenticação ou autorização inválida.' using errcode = '42501';
  end if;

  if p_draw_date < date_trunc('month',now() at time zone 'Europe/Lisbon')::date then
    raise exception 'Meses passados apenas mostram o histórico existente; não podem processar resultados com chaves atuais.' using errcode='22023';
  end if;

  if p_draw_date is null
    or extract(isodow from p_draw_date) not in (2, 5)
    or p_draw_date > current_date then
    raise exception 'Data de sorteio inválida.';
  end if;

  if cardinality(p_numbers) is distinct from 5
    or (select count(distinct n) from unnest(p_numbers) as values_list(n)) <> 5
    or exists (select 1 from unnest(p_numbers) as values_list(n) where n is null or n < 1 or n > 50) then
    raise exception 'Resultado inválido: são necessários cinco números únicos entre 1 e 50.';
  end if;
  if cardinality(p_stars) is distinct from 2
    or (select count(distinct s) from unnest(p_stars) as values_list(s)) <> 2
    or exists (select 1 from unnest(p_stars) as values_list(s) where s is null or s < 1 or s > 12) then
    raise exception 'Resultado inválido: são necessárias duas estrelas únicas entre 1 e 12.';
  end if;

  if auth.role() = 'service_role' then
    if p_draw_number is null
      or p_draw_number !~ '^[0-9]{3}/[0-9]{4}$'
      or split_part(p_draw_number, '/', 2) <> extract(year from p_draw_date)::integer::text then
      raise exception 'Número oficial do sorteio inválido.';
    end if;
  end if;

  if p_prizes is null or jsonb_typeof(p_prizes) is distinct from 'object' then
    raise exception 'A tabela de prémios tem de ser um objeto JSON.';
  end if;
  for prize_entry in select key, value from jsonb_each(p_prizes)
  loop
    if prize_entry.key !~ '^(?:[1-9]|1[0-3])$'
      or jsonb_typeof(prize_entry.value) is distinct from 'number'
      or (prize_entry.value #>> '{}')::numeric <= 0 then
      raise exception 'Tabela de prémios inválida.';
    end if;
  end loop;

  insert into public.euromillions_results as existing(
    club_id,draw_date,numbers,stars,created_by,official_draw_number,prize_table,source,imported_at
  ) values(
    target_club,p_draw_date,p_numbers,p_stars,auth.uid(),p_draw_number,p_prizes,p_source,now()
  )
  on conflict (club_id,draw_date) do update set
    numbers=excluded.numbers,stars=excluded.stars,
    created_by=coalesce(excluded.created_by, existing.created_by),
    official_draw_number=excluded.official_draw_number,prize_table=excluded.prize_table,
    source=excluded.source,imported_at=excluded.imported_at
  returning existing.id into rid;

  select coalesce((select value::numeric from public.club_settings where club_id=target_club and key='euromillions_fine_per_miss'),0.10) into fine_unit;

  for p in select * from public.euromillions_players where club_id=target_club and status='active' loop
    hit_n := (select count(*) from unnest(p.numbers) n where n=any(p_numbers));
    hit_s := (select count(*) from unnest(p.stars) s where s=any(p_stars));
    miss_n := 5-hit_n;
    miss_s := 2-hit_s;

    insert into public.euromillions_fines(club_id,result_id,player_id,missed_numbers,missed_stars,fine_amount)
    values(target_club,rid,p.id,miss_n,miss_s,(miss_n+miss_s)*fine_unit)
    on conflict (result_id,player_id) do update set
      missed_numbers=excluded.missed_numbers,missed_stars=excluded.missed_stars,fine_amount=excluded.fine_amount;

    cat := public.euromillions_prize_category_v1(hit_n,hit_s);
    if cat is not null then
      prize := coalesce((p_prizes->>cat::text)::numeric,0);
      if prize > 0 then
        insert into public.euromillions_prizes(club_id,result_id,player_id,category,matched_numbers,matched_stars,prize_amount)
        values(target_club,rid,p.id,cat,hit_n,hit_s,prize)
        on conflict (result_id,player_id) do update set
          category=excluded.category,matched_numbers=excluded.matched_numbers,
          matched_stars=excluded.matched_stars,prize_amount=excluded.prize_amount;
      else
        delete from public.euromillions_prizes where result_id=rid and player_id=p.id and received_amount=0;
      end if;
    else
      delete from public.euromillions_prizes where result_id=rid and player_id=p.id and received_amount=0;
    end if;
  end loop;
  return rid;
end; $$;

revoke all on function public.process_euromillions_official_result_v1(uuid,date,text,integer[],integer[],jsonb,text)
  from public, anon;
grant execute on function public.process_euromillions_official_result_v1(uuid,date,text,integer[],integer[],jsonb,text)
  to authenticated, service_role;

-- Close the legacy direct processing path under the same historical rule.
create or replace function public.process_euromillions_result_v1(
  target_club uuid,p_draw_date date,p_numbers integer[],p_stars integer[]
) returns uuid language plpgsql security definer set search_path=pg_catalog, public, pg_temp as $$
declare rid uuid; fine_unit numeric; p record; mn int; ms int;
begin
  if auth.uid() is null or not public.has_club_access(target_club) then
    raise exception 'Autenticação e acesso ao clube necessários.' using errcode='42501';
  end if;
  if not public.has_club_permission(target_club,'manageLottery') then
    raise exception 'Sem permissão para processar sorteios.';
  end if;
  if p_draw_date < date_trunc('month',now() at time zone 'Europe/Lisbon')::date then
    raise exception 'Meses passados apenas mostram o histórico existente.' using errcode='22023';
  end if;
  if cardinality(p_numbers)<>5 or cardinality(p_stars)<>2 then raise exception 'Resultado inválido.'; end if;
  insert into public.euromillions_results(club_id,draw_date,numbers,stars,created_by)
  values(target_club,p_draw_date,p_numbers,p_stars,auth.uid())
  on conflict(club_id,draw_date) do update set
    numbers=excluded.numbers,stars=excluded.stars,created_by=excluded.created_by
  returning id into rid;

  select coalesce((select value::numeric from public.club_settings
    where club_id=target_club and key='euromillions_fine_per_miss'),0.10)
  into fine_unit;

  for p in select * from public.euromillions_players where club_id=target_club and status='active' loop
    mn:=5-(select count(*) from unnest(p.numbers) n where n=any(p_numbers));
    ms:=2-(select count(*) from unnest(p.stars) s where s=any(p_stars));
    insert into public.euromillions_fines(
      club_id,result_id,player_id,missed_numbers,missed_stars,fine_amount
    ) values(target_club,rid,p.id,mn,ms,(mn+ms)*fine_unit)
    on conflict(result_id,player_id) do update set
      missed_numbers=excluded.missed_numbers,
      missed_stars=excluded.missed_stars,
      fine_amount=excluded.fine_amount;
  end loop;
  return rid;
end; $$;
revoke all on function public.process_euromillions_result_v1(uuid,date,integer[],integer[])
  from public, anon, authenticated, service_role;
grant execute on function public.process_euromillions_result_v1(uuid,date,integer[],integer[]) to authenticated;

commit;
