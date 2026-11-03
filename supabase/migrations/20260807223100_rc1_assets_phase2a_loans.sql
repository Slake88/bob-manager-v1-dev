create or replace function public.asset_loan_v1(target_club uuid,p_asset uuid,p_borrower_type text,p_member uuid default null,p_event uuid default null,p_external_name text default null,p_expected_return timestamptz default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_name text; begin
if not public.has_club_permission(target_club,'manageAssets') then raise exception 'Sem autorização para gerir património.'; end if;
select name into v_name from public.inventory_assets where id=p_asset and club_id=target_club and active=true for update;
if v_name is null then raise exception 'Bem patrimonial inválido.'; end if;
if exists(select 1 from public.asset_loans where asset_id=p_asset and returned_at is null) then raise exception 'Este bem já se encontra emprestado ou associado.'; end if;
if p_borrower_type not in ('member','external','event') then raise exception 'Tipo de destinatário inválido.'; end if;
insert into public.asset_loans(club_id,asset_id,borrower_type,member_id,event_id,external_name,expected_return_at,notes,created_by)
values(target_club,p_asset,p_borrower_type,p_member,p_event,nullif(trim(coalesce(p_external_name,'')),''),p_expected_return,nullif(trim(coalesce(p_notes,'')),''),auth.uid()) returning id into v_id;
insert into public.asset_events(club_id,asset_id,event_type,title,description,metadata,created_by)
values(target_club,p_asset,'loan','Bem emprestado / associado',nullif(trim(coalesce(p_notes,'')),''),jsonb_build_object('loan_id',v_id,'borrower_type',p_borrower_type,'expected_return_at',p_expected_return),auth.uid());
return v_id; end; $$;
grant execute on function public.asset_loan_v1(uuid,uuid,text,uuid,uuid,text,timestamptz,text) to authenticated;

create or replace function public.asset_return_v1(target_club uuid,p_loan uuid,p_condition text default null,p_notes text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_asset uuid; begin
if not public.has_club_permission(target_club,'manageAssets') then raise exception 'Sem autorização para gerir património.'; end if;
select asset_id into v_asset from public.asset_loans where id=p_loan and club_id=target_club and returned_at is null for update;
if v_asset is null then raise exception 'Empréstimo ativo não encontrado.'; end if;
update public.asset_loans set returned_at=now(),returned_condition=p_condition,return_notes=nullif(trim(coalesce(p_notes,'')),''),updated_at=now() where id=p_loan;
if p_condition in ('excellent','good','regular','maintenance','damaged') then update public.inventory_assets set condition=p_condition,updated_at=now() where id=v_asset; end if;
insert into public.asset_events(club_id,asset_id,event_type,title,description,metadata,created_by)
values(target_club,v_asset,'return','Bem devolvido',nullif(trim(coalesce(p_notes,'')),''),jsonb_build_object('loan_id',p_loan,'condition',p_condition),auth.uid());
end; $$;
grant execute on function public.asset_return_v1(uuid,uuid,text,text) to authenticated;
