create or replace function public.inventory_count_start_v1(target_club uuid,p_name text,p_location uuid default null,p_event uuid default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare sid uuid;
begin
 if not has_club_permission(target_club,'performInventoryCount') then raise exception 'Sem permissão para realizar inventário físico.'; end if;
 insert into inventory_count_sessions(club_id,name,location_id,event_id,status,notes,started_by) values(target_club,coalesce(nullif(trim(p_name),''),'Inventário físico'),p_location,p_event,'counting',nullif(trim(p_notes),''),auth.uid()) returning id into sid;
 insert into inventory_count_items(session_id,product_id,variant_id,theoretical_qty,unit_cost)
 select sid,p.id,pv.id,pv.current_stock,coalesce(pv.cost,p.cost,0)
 from products p join product_variants pv on pv.product_id=p.id and pv.active=true
 where p.club_id=target_club and p.active=true;
 insert into inventory_count_items(session_id,product_id,variant_id,theoretical_qty,unit_cost)
 select sid,p.id,null,p.current_stock,coalesce(p.cost,0)
 from products p where p.club_id=target_club and p.active=true and not exists(select 1 from product_variants pv where pv.product_id=p.id and pv.active=true);
 return sid;
end $$;

create or replace function public.inventory_count_set_qty_v1(target_club uuid,p_item uuid,p_counted numeric,p_notes text default null,p_recounted boolean default false)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not has_club_permission(target_club,'performInventoryCount') then raise exception 'Sem permissão para realizar inventário físico.'; end if;
 update inventory_count_items i set counted_qty=p_counted,notes=nullif(trim(p_notes),''),recounted=p_recounted,counted_by=auth.uid(),counted_at=now()
 from inventory_count_sessions s where i.id=p_item and i.session_id=s.id and s.club_id=target_club and s.status in ('counting','review');
 if not found then raise exception 'Linha de inventário não encontrada ou sessão fechada.'; end if;
end $$;

create or replace function public.inventory_count_finalize_v1(target_club uuid,p_session uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r record; adjusted int:=0; total_diff numeric:=0; value_diff numeric:=0;
begin
 if not has_club_permission(target_club,'performInventoryCount') then raise exception 'Sem permissão para concluir inventário físico.'; end if;
 if exists(select 1 from inventory_count_items i join inventory_count_sessions s on s.id=i.session_id where s.id=p_session and s.club_id=target_club and i.counted_qty is null) then raise exception 'Existem artigos por contar.'; end if;
 for r in select i.* from inventory_count_items i join inventory_count_sessions s on s.id=i.session_id where s.id=p_session and s.club_id=target_club and s.status in ('counting','review') loop
   if r.difference <> 0 then
     if r.variant_id is null then update products set current_stock=r.counted_qty where id=r.product_id and club_id=target_club;
     else update product_variants set current_stock=r.counted_qty where id=r.variant_id and product_id=r.product_id; end if;
     insert into stock_movements(club_id,product_id,variant_id,kind,quantity,unit_cost,notes,created_by)
       values(target_club,r.product_id,r.variant_id,'adjustment',r.difference,r.unit_cost,'Ajuste por inventário físico '||p_session::text,auth.uid());
     adjusted:=adjusted+1; total_diff:=total_diff+r.difference; value_diff:=value_diff+(r.difference*r.unit_cost);
   end if;
 end loop;
 update products p set current_stock=(select coalesce(sum(pv.current_stock),0) from product_variants pv where pv.product_id=p.id and pv.active=true)
 where p.club_id=target_club and exists(select 1 from inventory_count_items i where i.session_id=p_session and i.product_id=p.id and i.variant_id is not null);
 update inventory_count_sessions set status='completed',completed_by=auth.uid(),completed_at=now() where id=p_session and club_id=target_club and status in ('counting','review');
 if not found then raise exception 'Sessão não encontrada ou já concluída.'; end if;
 return jsonb_build_object('adjusted_items',adjusted,'net_quantity_difference',total_diff,'value_difference',value_diff);
end $$;
