create table public.imports (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  requested_by uuid references public.profiles(id) on delete set null,
  target text not null check (target in ('members','inventory_products','events','fee_plans')),
  source_filename text not null,
  source_format text not null check (source_format in ('csv','xlsx')),
  status text not null default 'draft' check (status in ('draft','ready','applied','reverted','failed')),
  mapping jsonb not null default '{}'::jsonb,
  total_rows integer not null default 0 check (total_rows >= 0),
  valid_rows integer not null default 0 check (valid_rows >= 0),
  invalid_rows integer not null default 0 check (invalid_rows >= 0),
  applied_rows integer not null default 0 check (applied_rows >= 0),
  error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  applied_at timestamptz,
  reverted_at timestamptz
);
create index imports_club_created_at_idx on public.imports (club_id, created_at desc);
create index imports_requested_by_idx on public.imports (requested_by) where requested_by is not null;

create table public.import_rows (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null references public.imports(id) on delete cascade,
  row_number integer not null check (row_number > 0),
  source_data jsonb not null default '{}'::jsonb,
  mapped_data jsonb not null default '{}'::jsonb,
  validation_errors text[] not null default array[]::text[],
  target_row_id uuid,
  applied_snapshot jsonb,
  applied_at timestamptz,
  reverted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (import_id, row_number)
);
create index import_rows_import_row_idx on public.import_rows (import_id, row_number);
create index import_rows_target_row_idx on public.import_rows (target_row_id) where target_row_id is not null;
alter table public.imports enable row level security;
alter table public.import_rows enable row level security;

create or replace function public.import_target_allowed_v1(target_club uuid, p_target text)
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (
    public.has_club_role(target_club,array['president','vice_president','admin','administrator','super_admin']::text[])
    or (
      public.has_club_permission(target_club, 'manageImports') and
      case p_target
        when 'members' then public.has_club_permission(target_club, 'manageMembers')
        when 'inventory_products' then public.has_club_permission(target_club, 'manageInventory')
        when 'events' then public.has_club_permission(target_club, 'manageEvents')
        when 'fee_plans' then public.has_club_permission(target_club, 'manageFees')
        else false
      end
    )
  );
$$;
revoke all on function public.import_target_allowed_v1(uuid,text) from public, anon;
grant execute on function public.import_target_allowed_v1(uuid,text) to authenticated, service_role;

create policy imports_authorized_read on public.imports for select to authenticated
using (public.import_target_allowed_v1(club_id, target));
create policy import_rows_authorized_read on public.import_rows for select to authenticated
using (exists (select 1 from public.imports i where i.id=import_rows.import_id and public.import_target_allowed_v1(i.club_id,i.target)));
revoke all on table public.imports from public, anon, authenticated;
revoke all on table public.import_rows from public, anon, authenticated;
grant select on table public.imports to authenticated;
grant select on table public.import_rows to authenticated;
grant select, insert, update, delete on table public.imports to service_role;
grant select, insert, update, delete on table public.import_rows to service_role;

create or replace function public.import_parse_date_v1(p_value text)
returns date language plpgsql immutable set search_path = public as $$
declare v text := nullif(btrim(p_value), '');
begin
  if v is null then return null; end if;
  if v ~ '^\d{2}/\d{2}/\d{4}$' then return to_date(v, 'DD/MM/YYYY'); end if;
  return v::date;
end; $$;

create or replace function public.import_parse_timestamptz_v1(p_value text)
returns timestamptz language plpgsql stable set search_path = public as $$
declare v text := nullif(btrim(p_value), '');
begin
  if v is null then return null; end if;
  if v ~ '^\d{2}/\d{2}/\d{4} \d{2}:\d{2}$' then return to_timestamp(v, 'DD/MM/YYYY HH24:MI')::timestamptz; end if;
  if v ~ '^\d{2}/\d{2}/\d{4}$' then return to_timestamp(v, 'DD/MM/YYYY')::timestamptz; end if;
  return v::timestamptz;
end; $$;

create or replace function public.import_parse_numeric_v1(p_value text, p_default numeric default null)
returns numeric language plpgsql immutable set search_path = public as $$
declare v text := nullif(btrim(p_value), '');
begin
  if v is null then return p_default; end if;
  v := replace(replace(v, '€', ''), ' ', '');
  if position(',' in v)>0 and position('.' in v)>0 then
    if strpos(reverse(v), ',') < strpos(reverse(v), '.') then
      v := replace(v,'.',''); v := replace(v,',','.');
    else v := replace(v,',',''); end if;
  else v := replace(v,',','.'); end if;
  return v::numeric;
end; $$;

create or replace function public.import_parse_boolean_v1(p_value text, p_default boolean default null)
returns boolean language plpgsql immutable set search_path = public as $$
declare v text := lower(nullif(btrim(p_value), ''));
begin
  if v is null then return p_default; end if;
  if v in ('true','1','sim','yes','y','s') then return true; end if;
  if v in ('false','0','nao','não','no','n') then return false; end if;
  raise exception 'boolean inválido';
end; $$;

create or replace function public.import_validate_row_v1(target_club uuid,p_target text,p_data jsonb)
returns text[] language plpgsql security definer set search_path = public as $$
declare e text[]:=array[]::text[]; v text; n numeric; i integer; d1 timestamptz; d2 timestamptz;
begin
  if p_data is null or jsonb_typeof(p_data)<>'object' then return array['Linha inválida.']; end if;
  case p_target
    when 'members' then
      if nullif(btrim(p_data->>'full_name'),'') is null then e:=array_append(e,'Nome completo é obrigatório.'); end if;
      v:=nullif(btrim(p_data->>'member_number'),'');
      if v is not null then
        begin i:=v::integer; if i<=0 then e:=array_append(e,'Número de membro deve ser positivo.'); end if;
        exception when others then e:=array_append(e,'Número de membro inválido.'); end;
        if not ('Número de membro inválido.'=any(e)) and i is not null and exists(select 1 from public.members m where m.club_id=target_club and m.member_number=i) then e:=array_append(e,'Número de membro já existe.'); end if;
      end if;
      v:=coalesce(nullif(btrim(p_data->>'status'),''),'active');
      if v not in ('active','suspended','honorary','former','prospect','full_color','deceased') then e:=array_append(e,'Estado do membro inválido.'); end if;
      foreach v in array array[p_data->>'birth_date',p_data->>'joined_at',p_data->>'prospect_joined_at',p_data->>'full_colors_at'] loop
        if nullif(btrim(v),'') is not null then begin perform public.import_parse_date_v1(v); exception when others then e:=array_append(e,'Existe uma data inválida.'); exit; end; end if;
      end loop;
    when 'inventory_products' then
      if nullif(btrim(p_data->>'name'),'') is null then e:=array_append(e,'Nome do produto é obrigatório.'); end if;
      v:=coalesce(nullif(btrim(p_data->>'inventory_area'),''),'shop'); if v not in ('shop','bar') then e:=array_append(e,'Área deve ser shop ou bar.'); end if;
      foreach v in array array[p_data->>'cost',p_data->>'sale_price',p_data->>'minimum_stock',p_data->>'units_per_purchase',p_data->>'purchase_cost'] loop
        if nullif(btrim(v),'') is not null then begin n:=public.import_parse_numeric_v1(v,0); if n<0 then e:=array_append(e,'Valores numéricos não podem ser negativos.'); exit; end if; exception when others then e:=array_append(e,'Existe um valor numérico inválido.'); exit; end; end if;
      end loop;
      foreach v in array array[p_data->>'active',p_data->>'institutional_delivery'] loop
        if nullif(btrim(v),'') is not null then begin perform public.import_parse_boolean_v1(v,false); exception when others then e:=array_append(e,'Existe um valor Sim/Não inválido.'); exit; end; end if;
      end loop;
    when 'events' then
      if nullif(btrim(p_data->>'name'),'') is null then e:=array_append(e,'Nome do evento é obrigatório.'); end if;
      v:=coalesce(nullif(btrim(p_data->>'status'),''),'draft'); if v not in ('draft','published','active','completed','cancelled') then e:=array_append(e,'Estado do evento inválido.'); end if;
      begin d1:=public.import_parse_timestamptz_v1(p_data->>'starts_at'); exception when others then e:=array_append(e,'Data/hora de início inválida.'); end;
      begin d2:=public.import_parse_timestamptz_v1(p_data->>'ends_at'); exception when others then e:=array_append(e,'Data/hora de fim inválida.'); end;
      if d1 is not null and d2 is not null and d2<d1 then e:=array_append(e,'Fim não pode ser anterior ao início.'); end if;
      v:=nullif(btrim(p_data->>'capacity'),''); if v is not null then begin i:=v::integer; if i<0 then e:=array_append(e,'Capacidade não pode ser negativa.'); end if; exception when others then e:=array_append(e,'Capacidade inválida.'); end; end if;
      v:=nullif(btrim(p_data->>'budget'),''); if v is not null then begin n:=public.import_parse_numeric_v1(v,0); if n<0 then e:=array_append(e,'Orçamento não pode ser negativo.'); end if; exception when others then e:=array_append(e,'Orçamento inválido.'); end; end if;
    when 'fee_plans' then
      if nullif(btrim(p_data->>'name'),'') is null then e:=array_append(e,'Nome do plano é obrigatório.'); end if;
      begin n:=public.import_parse_numeric_v1(p_data->>'amount',null); if n is null then e:=array_append(e,'Valor é obrigatório.'); elsif n<0 then e:=array_append(e,'Valor não pode ser negativo.'); end if; exception when others then e:=array_append(e,'Valor inválido.'); end;
      v:=coalesce(nullif(btrim(p_data->>'frequency'),''),'monthly'); if v not in ('monthly','quarterly','annual','custom') then e:=array_append(e,'Frequência inválida.'); end if;
      v:=nullif(btrim(p_data->>'due_day'),''); if v is not null then begin i:=v::integer; if i<1 or i>31 then e:=array_append(e,'Dia de vencimento deve estar entre 1 e 31.'); end if; exception when others then e:=array_append(e,'Dia de vencimento inválido.'); end; end if;
      v:=nullif(btrim(p_data->>'active'),''); if v is not null then begin perform public.import_parse_boolean_v1(v,true); exception when others then e:=array_append(e,'Ativo deve ser Sim/Não.'); end; end if;
    else e:=array_append(e,'Destino de importação inválido.');
  end case;
  return e;
end; $$;

revoke all on function public.import_validate_row_v1(uuid,text,jsonb) from public, anon, authenticated;
revoke all on function public.import_parse_date_v1(text) from public, anon, authenticated;
revoke all on function public.import_parse_timestamptz_v1(text) from public, anon, authenticated;
revoke all on function public.import_parse_numeric_v1(text,numeric) from public, anon, authenticated;
revoke all on function public.import_parse_boolean_v1(text,boolean) from public, anon, authenticated;

create or replace function public.begin_import_v1(target_club uuid,p_target text,p_source_filename text,p_source_format text,p_mapping jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_name text:=left(coalesce(nullif(btrim(p_source_filename),''),'importacao'),180); v_format text:=lower(coalesce(nullif(btrim(p_source_format),''),''));
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  if not public.import_target_allowed_v1(target_club,p_target) then raise exception 'Sem permissão para este destino de importação.'; end if;
  if v_format not in ('csv','xlsx') then raise exception 'Formato de importação inválido.'; end if;
  if p_mapping is null or jsonb_typeof(p_mapping)<>'object' then raise exception 'Mapeamento inválido.'; end if;
  insert into public.imports(club_id,requested_by,target,source_filename,source_format,mapping) values(target_club,auth.uid(),p_target,v_name,v_format,p_mapping) returning id into v_id;
  insert into public.audit_log(club_id,actor_id,entity_type,entity_id,action,after_data,data) values(target_club,auth.uid(),'import',v_id::text,'import_started',jsonb_build_object('target',p_target,'source_format',v_format),jsonb_build_object('import_id',v_id));
  return v_id;
end; $$;

create or replace function public.stage_import_rows_v1(target_club uuid,p_import uuid,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_import public.imports%rowtype; item jsonb; v_row_number integer; v_source jsonb; v_mapped jsonb; v_errors text[]; v_total integer; v_invalid integer;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  select * into v_import from public.imports where id=p_import and club_id=target_club and requested_by=auth.uid() for update;
  if not found then raise exception 'Importação não encontrada.'; end if;
  if not public.import_target_allowed_v1(target_club,v_import.target) then raise exception 'Sem permissão para esta importação.'; end if;
  if v_import.status not in ('draft','ready','failed') then raise exception 'Esta importação já não pode ser alterada.'; end if;
  if p_rows is null or jsonb_typeof(p_rows)<>'array' then raise exception 'Linhas inválidas.'; end if;
  v_total:=jsonb_array_length(p_rows); if v_total<1 or v_total>1000 then raise exception 'A importação deve ter entre 1 e 1000 linhas.'; end if;
  if octet_length(p_rows::text)>5*1024*1024 then raise exception 'Dados de importação demasiado grandes.'; end if;
  delete from public.import_rows where import_id=p_import;
  for item in select value from jsonb_array_elements(p_rows) loop
    v_row_number:=coalesce((item->>'row_number')::integer,0); v_source:=coalesce(item->'source_data','{}'::jsonb); v_mapped:=coalesce(item->'mapped_data','{}'::jsonb);
    if v_row_number<=0 then raise exception 'Número de linha inválido.'; end if;
    if jsonb_typeof(v_source)<>'object' or jsonb_typeof(v_mapped)<>'object' then raise exception 'Conteúdo de linha inválido.'; end if;
    v_errors:=public.import_validate_row_v1(target_club,v_import.target,v_mapped);
    insert into public.import_rows(import_id,row_number,source_data,mapped_data,validation_errors) values(p_import,v_row_number,v_source,v_mapped,v_errors);
  end loop;
  if v_import.target='members' then
    update public.import_rows r set validation_errors=array_append(r.validation_errors,'Número de membro duplicado no ficheiro.'),updated_at=now()
    where r.import_id=p_import and nullif(btrim(r.mapped_data->>'member_number'),'') is not null
      and r.mapped_data->>'member_number' in (select mapped_data->>'member_number' from public.import_rows where import_id=p_import and nullif(btrim(mapped_data->>'member_number'),'') is not null group by mapped_data->>'member_number' having count(*)>1)
      and not ('Número de membro duplicado no ficheiro.'=any(r.validation_errors));
  end if;
  select count(*),count(*) filter(where cardinality(validation_errors)>0) into v_total,v_invalid from public.import_rows where import_id=p_import;
  update public.imports set total_rows=v_total,valid_rows=v_total-v_invalid,invalid_rows=v_invalid,applied_rows=0,error_code=null,status=case when v_invalid=0 then 'ready' else 'draft' end,updated_at=now() where id=p_import;
  insert into public.audit_log(club_id,actor_id,entity_type,entity_id,action,after_data,data) values(target_club,auth.uid(),'import',p_import::text,'import_staged',jsonb_build_object('total_rows',v_total,'valid_rows',v_total-v_invalid,'invalid_rows',v_invalid),jsonb_build_object('import_id',p_import));
  return jsonb_build_object('total_rows',v_total,'valid_rows',v_total-v_invalid,'invalid_rows',v_invalid,'status',case when v_invalid=0 then 'ready' else 'draft' end);
end; $$;

create or replace function public.update_import_row_v1(target_club uuid,p_import uuid,p_row uuid,p_mapped_data jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_import public.imports%rowtype; v_errors text[]; v_total integer; v_invalid integer;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  select * into v_import from public.imports where id=p_import and club_id=target_club and requested_by=auth.uid() for update;
  if not found then raise exception 'Importação não encontrada.'; end if;
  if not public.import_target_allowed_v1(target_club,v_import.target) then raise exception 'Sem permissão.'; end if;
  if v_import.status not in ('draft','ready','failed') then raise exception 'Esta importação já não pode ser editada.'; end if;
  if p_mapped_data is null or jsonb_typeof(p_mapped_data)<>'object' then raise exception 'Dados mapeados inválidos.'; end if;
  v_errors:=public.import_validate_row_v1(target_club,v_import.target,p_mapped_data);
  update public.import_rows set mapped_data=p_mapped_data,validation_errors=v_errors,updated_at=now() where id=p_row and import_id=p_import;
  if not found then raise exception 'Linha não encontrada.'; end if;
  if v_import.target='members' then
    update public.import_rows r set validation_errors=array_remove(r.validation_errors,'Número de membro duplicado no ficheiro.'),updated_at=now() where r.import_id=p_import;
    update public.import_rows r set validation_errors=array_append(r.validation_errors,'Número de membro duplicado no ficheiro.'),updated_at=now()
      where r.import_id=p_import and nullif(btrim(r.mapped_data->>'member_number'),'') is not null and r.mapped_data->>'member_number' in (select mapped_data->>'member_number' from public.import_rows where import_id=p_import and nullif(btrim(mapped_data->>'member_number'),'') is not null group by mapped_data->>'member_number' having count(*)>1);
  end if;
  select count(*),count(*) filter(where cardinality(validation_errors)>0) into v_total,v_invalid from public.import_rows where import_id=p_import;
  update public.imports set total_rows=v_total,valid_rows=v_total-v_invalid,invalid_rows=v_invalid,status=case when v_invalid=0 then 'ready' else 'draft' end,error_code=null,updated_at=now() where id=p_import;
  select validation_errors into v_errors from public.import_rows where id=p_row;
  return jsonb_build_object('validation_errors',to_jsonb(v_errors),'status',case when v_invalid=0 then 'ready' else 'draft' end,'valid_rows',v_total-v_invalid,'invalid_rows',v_invalid);
end; $$;

create or replace function public.apply_import_v1(target_club uuid,p_import uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_import public.imports%rowtype; r public.import_rows%rowtype; v_id uuid; v_updated timestamptz; v_count integer:=0; v_data jsonb;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  select * into v_import from public.imports where id=p_import and club_id=target_club for update;
  if not found then raise exception 'Importação não encontrada.'; end if;
  if not public.import_target_allowed_v1(target_club,v_import.target) then raise exception 'Sem permissão.'; end if;
  if v_import.status<>'ready' or v_import.invalid_rows<>0 or v_import.total_rows<1 then raise exception 'A importação ainda não está pronta.'; end if;
  begin
    for r in select * from public.import_rows where import_id=p_import order by row_number loop
      v_data:=r.mapped_data;
      case v_import.target
        when 'members' then
          insert into public.members(club_id,member_number,full_name,nickname,email,phone,birth_date,joined_at,status,prospect_joined_at,full_colors_at,created_by,updated_by)
          values(target_club,nullif(btrim(v_data->>'member_number'),'')::integer,btrim(v_data->>'full_name'),nullif(btrim(v_data->>'nickname'),''),nullif(btrim(v_data->>'email'),''),nullif(btrim(v_data->>'phone'),''),public.import_parse_date_v1(v_data->>'birth_date'),public.import_parse_date_v1(v_data->>'joined_at'),coalesce(nullif(btrim(v_data->>'status'),''),'active')::public.member_status,public.import_parse_date_v1(v_data->>'prospect_joined_at'),public.import_parse_date_v1(v_data->>'full_colors_at'),auth.uid(),auth.uid()) returning id,updated_at into v_id,v_updated;
        when 'inventory_products' then
          insert into public.products(club_id,name,sku,category,unit,cost,sale_price,minimum_stock,active,inventory_area,description,supplier,institutional_delivery,purchase_unit,consumption_unit,units_per_purchase,purchase_cost,created_by,updated_by)
          values(target_club,btrim(v_data->>'name'),nullif(btrim(v_data->>'sku'),''),nullif(btrim(v_data->>'category'),''),coalesce(nullif(btrim(v_data->>'unit'),''),'unit'),public.import_parse_numeric_v1(v_data->>'cost',0),public.import_parse_numeric_v1(v_data->>'sale_price',0),public.import_parse_numeric_v1(v_data->>'minimum_stock',0),public.import_parse_boolean_v1(v_data->>'active',true),coalesce(nullif(btrim(v_data->>'inventory_area'),''),'shop'),nullif(btrim(v_data->>'description'),''),nullif(btrim(v_data->>'supplier'),''),public.import_parse_boolean_v1(v_data->>'institutional_delivery',false),nullif(btrim(v_data->>'purchase_unit'),''),nullif(btrim(v_data->>'consumption_unit'),''),public.import_parse_numeric_v1(v_data->>'units_per_purchase',1),public.import_parse_numeric_v1(v_data->>'purchase_cost',0),auth.uid(),auth.uid()) returning id,updated_at into v_id,v_updated;
        when 'events' then
          insert into public.events(club_id,name,description,location,starts_at,ends_at,status,capacity,budget,event_mode_enabled,created_by,updated_by)
          values(target_club,btrim(v_data->>'name'),nullif(btrim(v_data->>'description'),''),nullif(btrim(v_data->>'location'),''),public.import_parse_timestamptz_v1(v_data->>'starts_at'),public.import_parse_timestamptz_v1(v_data->>'ends_at'),coalesce(nullif(btrim(v_data->>'status'),''),'draft')::public.event_status,nullif(btrim(v_data->>'capacity'),'')::integer,public.import_parse_numeric_v1(v_data->>'budget',0),false,auth.uid(),auth.uid()) returning id,updated_at into v_id,v_updated;
        when 'fee_plans' then
          insert into public.fee_plans(club_id,name,amount,frequency,due_day,active,created_by,updated_by)
          values(target_club,btrim(v_data->>'name'),public.import_parse_numeric_v1(v_data->>'amount',0),coalesce(nullif(btrim(v_data->>'frequency'),''),'monthly'),nullif(btrim(v_data->>'due_day'),'')::integer,public.import_parse_boolean_v1(v_data->>'active',true),auth.uid(),auth.uid()) returning id,updated_at into v_id,v_updated;
        else raise exception 'Destino inválido.';
      end case;
      update public.import_rows set target_row_id=v_id,applied_snapshot=jsonb_build_object('updated_at_epoch',extract(epoch from v_updated)),applied_at=now(),updated_at=now() where id=r.id;
      v_count:=v_count+1;
    end loop;
  exception when others then
    update public.imports set status='failed',error_code='apply_failed',updated_at=now() where id=p_import;
    insert into public.audit_log(club_id,actor_id,entity_type,entity_id,action,after_data,data) values(target_club,auth.uid(),'import',p_import::text,'import_failed',jsonb_build_object('error_code','apply_failed'),jsonb_build_object('import_id',p_import));
    return jsonb_build_object('success',false,'error_code','apply_failed');
  end;
  update public.import_rows set source_data='{}'::jsonb where import_id=p_import;
  update public.imports set status='applied',applied_rows=v_count,error_code=null,applied_at=now(),updated_at=now() where id=p_import;
  insert into public.audit_log(club_id,actor_id,entity_type,entity_id,action,after_data,data) values(target_club,auth.uid(),'import',p_import::text,'import_applied',jsonb_build_object('target',v_import.target,'applied_rows',v_count),jsonb_build_object('import_id',p_import));
  return jsonb_build_object('success',true,'applied_rows',v_count);
end; $$;

create or replace function public.rollback_import_v1(target_club uuid,p_import uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_import public.imports%rowtype; r public.import_rows%rowtype; v_updated timestamptz; v_expected double precision; v_blocked boolean; v_count integer:=0;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  select * into v_import from public.imports where id=p_import and club_id=target_club for update;
  if not found then raise exception 'Importação não encontrada.'; end if;
  if not public.import_target_allowed_v1(target_club,v_import.target) then raise exception 'Sem permissão.'; end if;
  if v_import.status<>'applied' then raise exception 'Apenas importações aplicadas podem ser revertidas.'; end if;
  begin
    for r in select * from public.import_rows where import_id=p_import order by row_number desc loop
      if r.target_row_id is null then raise exception 'Registo importado em falta.'; end if;
      v_expected:=(r.applied_snapshot->>'updated_at_epoch')::double precision; v_blocked:=false;
      case v_import.target
        when 'members' then
          select updated_at into v_updated from public.members where id=r.target_row_id and club_id=target_club; if not found then raise exception 'Membro importado já não existe.'; end if;
          if abs(extract(epoch from v_updated)-v_expected)>0.001 then raise exception 'Membro importado foi alterado depois da importação.'; end if;
          select exists(select 1 from public.member_motorcycles where member_id=r.target_row_id) or exists(select 1 from public.maintenance_records where member_id=r.target_row_id) or exists(select 1 from public.member_patch_awards where member_id=r.target_row_id) or exists(select 1 from public.member_positions where member_id=r.target_row_id) or exists(select 1 from public.financial_requests where member_id=r.target_row_id) or exists(select 1 from public.event_registrations where member_id=r.target_row_id) or exists(select 1 from public.event_volunteers where member_id=r.target_row_id) or exists(select 1 from public.shop_orders where member_id=r.target_row_id) or exists(select 1 from public.euromillions_players where member_id=r.target_row_id) or exists(select 1 from public.euromillions_participations where member_id=r.target_row_id) or exists(select 1 from public.asset_loans where member_id=r.target_row_id) or exists(select 1 from public.inventory_assets where responsible_member_id=r.target_row_id) or exists(select 1 from public.weekly_dinners where assigned_member_id=r.target_row_id) or exists(select 1 from public.weekly_officer_absences where member_id=r.target_row_id) or exists(select 1 from public.weekly_officer_swap_requests where requester_member_id=r.target_row_id or requested_member_id=r.target_row_id) into v_blocked;
          if v_blocked then raise exception 'Membro importado já possui dados associados.'; end if; delete from public.members where id=r.target_row_id and club_id=target_club;
        when 'inventory_products' then
          select updated_at into v_updated from public.products where id=r.target_row_id and club_id=target_club; if not found then raise exception 'Produto importado já não existe.'; end if;
          if abs(extract(epoch from v_updated)-v_expected)>0.001 then raise exception 'Produto importado foi alterado depois da importação.'; end if;
          select exists(select 1 from public.product_variants where product_id=r.target_row_id) or exists(select 1 from public.product_images where product_id=r.target_row_id) or exists(select 1 from public.stock_movements where product_id=r.target_row_id) or exists(select 1 from public.shop_order_items where product_id=r.target_row_id) or exists(select 1 from public.member_patch_awards where product_id=r.target_row_id) or exists(select 1 from public.bar_operations where product_id=r.target_row_id) or exists(select 1 from public.bar_consumption_session_items where product_id=r.target_row_id) or exists(select 1 from public.inventory_count_items where product_id=r.target_row_id) or exists(select 1 from public.inventory_prices where product_id=r.target_row_id) or exists(select 1 from public.inventory_visibility where product_id=r.target_row_id) into v_blocked;
          if v_blocked then raise exception 'Produto importado já possui dados associados.'; end if; delete from public.products where id=r.target_row_id and club_id=target_club;
        when 'events' then
          select updated_at into v_updated from public.events where id=r.target_row_id and club_id=target_club; if not found then raise exception 'Evento importado já não existe.'; end if;
          if abs(extract(epoch from v_updated)-v_expected)>0.001 then raise exception 'Evento importado foi alterado depois da importação.'; end if;
          select exists(select 1 from public.event_registrations where event_id=r.target_row_id) or exists(select 1 from public.event_volunteers where event_id=r.target_row_id) or exists(select 1 from public.event_partners where event_id=r.target_row_id) or exists(select 1 from public.treasury_transactions where event_id=r.target_row_id) or exists(select 1 from public.stock_movements where event_id=r.target_row_id) or exists(select 1 from public.inventory_locations where event_id=r.target_row_id) or exists(select 1 from public.inventory_count_sessions where event_id=r.target_row_id) or exists(select 1 from public.bar_operations where event_id=r.target_row_id) or exists(select 1 from public.bar_consumption_sessions where event_id=r.target_row_id) or exists(select 1 from public.asset_loans where event_id=r.target_row_id) into v_blocked;
          if v_blocked then raise exception 'Evento importado já possui dados associados.'; end if; delete from public.events where id=r.target_row_id and club_id=target_club;
        when 'fee_plans' then
          select updated_at into v_updated from public.fee_plans where id=r.target_row_id and club_id=target_club; if not found then raise exception 'Plano importado já não existe.'; end if;
          if v_updated is not null and abs(extract(epoch from v_updated)-v_expected)>0.001 then raise exception 'Plano importado foi alterado depois da importação.'; end if;
          if exists(select 1 from public.fee_obligations where fee_plan_id=r.target_row_id) then raise exception 'Plano importado já possui quotas associadas.'; end if; delete from public.fee_plans where id=r.target_row_id and club_id=target_club;
      end case;
      update public.import_rows set reverted_at=now(),updated_at=now() where id=r.id; v_count:=v_count+1;
    end loop;
  exception when others then
    insert into public.audit_log(club_id,actor_id,entity_type,entity_id,action,after_data,data) values(target_club,auth.uid(),'import',p_import::text,'import_rollback_blocked',jsonb_build_object('error_code','rollback_blocked'),jsonb_build_object('import_id',p_import));
    return jsonb_build_object('success',false,'error_code','rollback_blocked');
  end;
  update public.imports set status='reverted',reverted_at=now(),updated_at=now() where id=p_import;
  insert into public.audit_log(club_id,actor_id,entity_type,entity_id,action,after_data,data) values(target_club,auth.uid(),'import',p_import::text,'import_reverted',jsonb_build_object('reverted_rows',v_count),jsonb_build_object('import_id',p_import));
  return jsonb_build_object('success',true,'reverted_rows',v_count);
end; $$;

revoke all on function public.begin_import_v1(uuid,text,text,text,jsonb) from public, anon;
revoke all on function public.stage_import_rows_v1(uuid,uuid,jsonb) from public, anon;
revoke all on function public.update_import_row_v1(uuid,uuid,uuid,jsonb) from public, anon;
revoke all on function public.apply_import_v1(uuid,uuid) from public, anon;
revoke all on function public.rollback_import_v1(uuid,uuid) from public, anon;
grant execute on function public.begin_import_v1(uuid,text,text,text,jsonb) to authenticated, service_role;
grant execute on function public.stage_import_rows_v1(uuid,uuid,jsonb) to authenticated, service_role;
grant execute on function public.update_import_row_v1(uuid,uuid,uuid,jsonb) to authenticated, service_role;
grant execute on function public.apply_import_v1(uuid,uuid) to authenticated, service_role;
grant execute on function public.rollback_import_v1(uuid,uuid) to authenticated, service_role;