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
