-- Commit 14 — Fundação de Inventário: hardening inicial

-- 1) Inventário físico: apenas RPCs podem alterar sessões/linhas.
revoke all on function public.inventory_count_start_v1(uuid,text,uuid,uuid,text) from public, anon;
revoke all on function public.inventory_count_set_qty_v1(uuid,uuid,numeric,text,boolean) from public, anon;
revoke all on function public.inventory_count_finalize_v1(uuid,uuid) from public, anon;
grant execute on function public.inventory_count_start_v1(uuid,text,uuid,uuid,text) to authenticated;
grant execute on function public.inventory_count_set_qty_v1(uuid,uuid,numeric,text,boolean) to authenticated;
grant execute on function public.inventory_count_finalize_v1(uuid,uuid) to authenticated;

revoke all on table public.inventory_count_sessions from anon;
revoke all on table public.inventory_count_items from anon;
revoke insert, update, delete, truncate, references, trigger on table public.inventory_count_sessions from authenticated;
revoke insert, update, delete, truncate, references, trigger on table public.inventory_count_items from authenticated;
grant select on table public.inventory_count_sessions to authenticated;
grant select on table public.inventory_count_items to authenticated;

-- Remover caminhos de escrita direta; as alterações passam pelas RPCs security definer.
drop policy if exists inventory_count_sessions_manage on public.inventory_count_sessions;
drop policy if exists inventory_count_items_manage on public.inventory_count_items;
drop policy if exists inventory_count_sessions_read on public.inventory_count_sessions;
create policy inventory_count_sessions_read
on public.inventory_count_sessions for select to authenticated
using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists inventory_count_items_read on public.inventory_count_items;
create policy inventory_count_items_read
on public.inventory_count_items for select to authenticated
using (
  exists (
    select 1
    from public.inventory_count_sessions s
    where s.id = inventory_count_items.session_id
      and public.has_club_permission(s.club_id,'viewInventory')
  )
);

-- 2) Leitura de inventário obedece à permissão do módulo, não apenas à pertença ao clube.
drop policy if exists products_select on public.products;
create policy products_select
on public.products for select to authenticated
using (public.has_club_permission(club_id,'viewInventory'));

drop policy if exists stock_movements_select on public.stock_movements;
create policy stock_movements_select
on public.stock_movements for select to authenticated
using (public.has_club_permission(club_id,'viewInventory'));

drop policy if exists product_variants_read on public.product_variants;
create policy product_variants_read
on public.product_variants for select to authenticated
using (
  exists (
    select 1 from public.products p
    where p.id = product_variants.product_id
      and public.has_club_permission(p.club_id,'viewInventory')
  )
);

-- 3) O papel anon não precisa de acesso direto às tabelas-base do inventário.
revoke all on table public.products from anon;
revoke all on table public.product_variants from anon;
revoke all on table public.stock_movements from anon;
revoke all on table public.inventory_categories from anon;
revoke all on table public.inventory_locations from anon;
revoke all on table public.inventory_prices from anon;
revoke all on table public.inventory_visibility from anon;

-- Clientes autenticados não necessitam de capacidades estruturais perigosas.
revoke truncate, references, trigger on table public.products from authenticated;
revoke truncate, references, trigger on table public.product_variants from authenticated;
revoke truncate, references, trigger on table public.stock_movements from authenticated;
revoke truncate, references, trigger on table public.inventory_categories from authenticated;
revoke truncate, references, trigger on table public.inventory_locations from authenticated;
revoke truncate, references, trigger on table public.inventory_prices from authenticated;
revoke truncate, references, trigger on table public.inventory_visibility from authenticated;

-- 4) Validar local/evento e impedir quantidades negativas na contagem.
create or replace function public.inventory_count_start_v1(
  target_club uuid,
  p_name text,
  p_location uuid default null,
  p_event uuid default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare sid uuid;
begin
  if not public.has_club_permission(target_club,'performInventoryCount') then
    raise exception 'Sem permissão para realizar inventário físico.';
  end if;

  if p_location is not null and not exists (
    select 1 from public.inventory_locations l
    where l.id=p_location and l.club_id=target_club and l.active=true
  ) then
    raise exception 'Local de inventário inválido para este clube.';
  end if;

  if p_event is not null and not exists (
    select 1 from public.events e
    where e.id=p_event and e.club_id=target_club
  ) then
    raise exception 'Evento inválido para este clube.';
  end if;

  insert into public.inventory_count_sessions(
    club_id,name,location_id,event_id,status,notes,started_by
  ) values (
    target_club,
    coalesce(nullif(trim(p_name),''),'Inventário físico'),
    p_location,p_event,'counting',nullif(trim(p_notes),''),auth.uid()
  ) returning id into sid;

  insert into public.inventory_count_items(
    session_id,product_id,variant_id,theoretical_qty,unit_cost
  )
  select sid,p.id,pv.id,pv.current_stock,coalesce(pv.cost,p.cost,0)
  from public.products p
  join public.product_variants pv on pv.product_id=p.id and pv.active=true
  where p.club_id=target_club and p.active=true;

  insert into public.inventory_count_items(
    session_id,product_id,variant_id,theoretical_qty,unit_cost
  )
  select sid,p.id,null,p.current_stock,coalesce(p.cost,0)
  from public.products p
  where p.club_id=target_club and p.active=true
    and not exists (
      select 1 from public.product_variants pv
      where pv.product_id=p.id and pv.active=true
    );

  return sid;
end $$;

create or replace function public.inventory_count_set_qty_v1(
  target_club uuid,
  p_item uuid,
  p_counted numeric,
  p_notes text default null,
  p_recounted boolean default false
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.has_club_permission(target_club,'performInventoryCount') then
    raise exception 'Sem permissão para realizar inventário físico.';
  end if;
  if p_counted is null or p_counted < 0 then
    raise exception 'A quantidade contada não pode ser negativa.';
  end if;

  update public.inventory_count_items i
  set counted_qty=p_counted,
      notes=nullif(trim(p_notes),''),
      recounted=p_recounted,
      counted_by=auth.uid(),
      counted_at=now()
  from public.inventory_count_sessions s
  where i.id=p_item
    and i.session_id=s.id
    and s.club_id=target_club
    and s.status in ('counting','review');

  if not found then
    raise exception 'Linha de inventário não encontrada ou sessão fechada.';
  end if;
end $$;

create or replace function public.inventory_count_finalize_v1(
  target_club uuid,
  p_session uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare r record; adjusted int:=0; total_diff numeric:=0; value_diff numeric:=0;
begin
  if not public.has_club_permission(target_club,'performInventoryCount') then
    raise exception 'Sem permissão para concluir inventário físico.';
  end if;

  if exists (
    select 1
    from public.inventory_count_items i
    join public.inventory_count_sessions s on s.id=i.session_id
    where s.id=p_session and s.club_id=target_club and i.counted_qty is null
  ) then
    raise exception 'Existem artigos por contar.';
  end if;

  if exists (
    select 1
    from public.inventory_count_items i
    join public.inventory_count_sessions s on s.id=i.session_id
    where s.id=p_session and s.club_id=target_club and i.counted_qty < 0
  ) then
    raise exception 'Existem quantidades negativas na contagem.';
  end if;

  for r in
    select i.*
    from public.inventory_count_items i
    join public.inventory_count_sessions s on s.id=i.session_id
    where s.id=p_session and s.club_id=target_club and s.status in ('counting','review')
  loop
    if r.difference <> 0 then
      if r.variant_id is null then
        update public.products
        set current_stock=r.counted_qty
        where id=r.product_id and club_id=target_club;
      else
        update public.product_variants
        set current_stock=r.counted_qty
        where id=r.variant_id and product_id=r.product_id;
      end if;

      insert into public.stock_movements(
        club_id,product_id,variant_id,kind,quantity,unit_cost,notes,created_by
      ) values (
        target_club,r.product_id,r.variant_id,'adjustment',r.difference,r.unit_cost,
        'Ajuste por inventário físico '||p_session::text,auth.uid()
      );
      adjusted:=adjusted+1;
      total_diff:=total_diff+r.difference;
      value_diff:=value_diff+(r.difference*r.unit_cost);
    end if;
  end loop;

  update public.products p
  set current_stock=(
    select coalesce(sum(pv.current_stock),0)
    from public.product_variants pv
    where pv.product_id=p.id and pv.active=true
  )
  where p.club_id=target_club
    and exists (
      select 1 from public.inventory_count_items i
      where i.session_id=p_session and i.product_id=p.id and i.variant_id is not null
    );

  update public.inventory_count_sessions
  set status='completed',completed_by=auth.uid(),completed_at=now()
  where id=p_session and club_id=target_club and status in ('counting','review');

  if not found then
    raise exception 'Sessão não encontrada ou já concluída.';
  end if;

  return jsonb_build_object(
    'adjusted_items',adjusted,
    'net_quantity_difference',total_diff,
    'value_difference',value_diff
  );
end $$;

-- CREATE OR REPLACE preserva privilégios, mas reiteramos a superfície permitida.
revoke all on function public.inventory_count_start_v1(uuid,text,uuid,uuid,text) from public, anon;
revoke all on function public.inventory_count_set_qty_v1(uuid,uuid,numeric,text,boolean) from public, anon;
revoke all on function public.inventory_count_finalize_v1(uuid,uuid) from public, anon;
grant execute on function public.inventory_count_start_v1(uuid,text,uuid,uuid,text) to authenticated;
grant execute on function public.inventory_count_set_qty_v1(uuid,uuid,numeric,text,boolean) to authenticated;
grant execute on function public.inventory_count_finalize_v1(uuid,uuid) to authenticated;
