create or replace function public.activity_member_trigger_v1()
returns trigger language plpgsql security definer set search_path='public' as $$
begin
  if tg_op='INSERT' then
    perform public.emit_domain_event(new.club_id,'MemberCreated','member',new.id,
      jsonb_build_object('title','Novo membro registado','description',new.full_name,'route','members','priority','normal'));
  elsif new.full_name is distinct from old.full_name or new.status is distinct from old.status then
    perform public.emit_domain_event(new.club_id,'MemberUpdated','member',new.id,
      jsonb_build_object('title','Ficha de membro atualizada','description',new.full_name,'route','members','priority','low'));
  end if;
  return new;
end; $$;
drop trigger if exists trg_activity_members on public.members;
create trigger trg_activity_members after insert or update on public.members for each row execute function public.activity_member_trigger_v1();

create or replace function public.activity_event_trigger_v1()
returns trigger language plpgsql security definer set search_path='public' as $$
declare d text;
begin
  d:=case when new.starts_at is null then coalesce(new.location,'') else to_char(new.starts_at at time zone 'Europe/Lisbon','DD/MM/YYYY HH24:MI')||case when new.location is null or trim(new.location)='' then '' else ' · '||new.location end end;
  if tg_op='INSERT' then
    perform public.emit_domain_event(new.club_id,'EventCreated','event',new.id,
      jsonb_build_object('title','Novo evento: '||new.name,'description',d,'route','events','priority','high','push',true));
  elsif new.name is distinct from old.name or new.starts_at is distinct from old.starts_at or new.location is distinct from old.location or new.status is distinct from old.status then
    perform public.emit_domain_event(new.club_id,'EventUpdated','event',new.id,
      jsonb_build_object('title','Evento atualizado: '||new.name,'description',d,'route','events','priority','normal','push',true));
  end if;
  return new;
end; $$;
drop trigger if exists trg_activity_events on public.events;
create trigger trg_activity_events after insert or update on public.events for each row execute function public.activity_event_trigger_v1();

create or replace function public.activity_treasury_trigger_v1()
returns trigger language plpgsql security definer set search_path='public' as $$
begin
  perform public.emit_domain_event(new.club_id,'TreasuryTransactionCreated','transaction',new.id,
    jsonb_build_object('title',case when new.kind::text='income' then 'Receita registada' when new.kind::text='expense' then 'Despesa registada' else 'Transferência registada' end,
      'description',coalesce(new.description,'Movimento de tesouraria')||' · '||to_char(new.amount,'FM999999990D00')||' €','route','treasury','priority','normal','amount',new.amount,'kind',new.kind::text));
  return new;
end; $$;
drop trigger if exists trg_activity_treasury on public.treasury_transactions;
create trigger trg_activity_treasury after insert on public.treasury_transactions for each row execute function public.activity_treasury_trigger_v1();

create or replace function public.activity_fee_payment_trigger_v1()
returns trigger language plpgsql security definer set search_path='public' as $$
declare v_name text; v_obligation uuid;
begin
  select o.id,m.full_name into v_obligation,v_name from public.fee_obligations o join public.members m on m.id=o.member_id where o.id=new.obligation_id;
  perform public.emit_domain_event(new.club_id,'FeePaid','fee',v_obligation,
    jsonb_build_object('title','Quota recebida','description',coalesce(v_name,'Membro')||' · '||to_char(new.amount,'FM999999990D00')||' €','route','fees','priority','normal','amount',new.amount));
  return new;
end; $$;
drop trigger if exists trg_activity_fee_payments on public.fee_payments;
create trigger trg_activity_fee_payments after insert on public.fee_payments for each row execute function public.activity_fee_payment_trigger_v1();

create or replace function public.activity_euromillions_result_trigger_v1()
returns trigger language plpgsql security definer set search_path='public' as $$
begin
  if tg_op='INSERT' then
    perform public.emit_domain_event(new.club_id,'EuromillionsResultAvailable','euromillions',new.id,
      jsonb_build_object('title','Resultado Euromilhões disponível','description','Sorteio de '||to_char(new.draw_date,'DD/MM/YYYY'),'route','lottery','priority','normal','push',true));
  end if;
  return new;
end; $$;
drop trigger if exists trg_activity_euromillions_results on public.euromillions_results;
create trigger trg_activity_euromillions_results after insert on public.euromillions_results for each row execute function public.activity_euromillions_result_trigger_v1();

create or replace function public.activity_stock_trigger_v1()
returns trigger language plpgsql security definer set search_path='public' as $$
declare v_name text;
begin
  select name into v_name from public.products where id=new.product_id;
  perform public.emit_domain_event(new.club_id,'InventoryMovementCreated','inventory',new.id,
    jsonb_build_object('title','Movimento de inventário','description',coalesce(v_name,'Artigo')||' · '||new.quantity::text,'route','inventory','priority','low'));
  return new;
end; $$;
drop trigger if exists trg_activity_stock_movements on public.stock_movements;
create trigger trg_activity_stock_movements after insert on public.stock_movements for each row execute function public.activity_stock_trigger_v1();

create or replace function public.activity_document_trigger_v1()
returns trigger language plpgsql security definer set search_path='public' as $$
begin
  if tg_op='INSERT' then
    perform public.emit_domain_event(new.club_id,'DocumentCreated','document',new.id,
      jsonb_build_object('title','Novo documento','description',new.title,'route','documents','priority',case when new.sensitive then 'high' else 'normal' end,'push',true));
  end if;
  return new;
end; $$;
drop trigger if exists trg_activity_documents on public.documents;
create trigger trg_activity_documents after insert on public.documents for each row execute function public.activity_document_trigger_v1();

create or replace function public.activity_announcement_trigger_v1()
returns trigger language plpgsql security definer set search_path='public' as $$
begin
  if tg_op='INSERT' then
    perform public.emit_domain_event(new.club_id,'AnnouncementCreated','announcement',new.id,
      jsonb_build_object('title','Novo comunicado','description',new.title,'route','communication','priority','high','push',true));
  end if;
  return new;
end; $$;
drop trigger if exists trg_activity_announcements on public.announcements;
create trigger trg_activity_announcements after insert on public.announcements for each row execute function public.activity_announcement_trigger_v1();

create or replace function public.activity_permission_trigger_v1()
returns trigger language plpgsql security definer set search_path='public' as $$
begin
  perform public.emit_domain_event(new.club_id,'PermissionsUpdated','permission',null,
    jsonb_build_object('title','Permissões atualizadas','description','A matriz de acessos do clube foi alterada.','route','settings','priority','low'));
  return new;
end; $$;
drop trigger if exists trg_activity_role_permissions on public.club_role_permissions;
create trigger trg_activity_role_permissions after insert or update on public.club_role_permissions for each row execute function public.activity_permission_trigger_v1();

create or replace function public.activity_user_permission_trigger_v1()
returns trigger language plpgsql security definer set search_path='public' as $$
declare v_club uuid; v_profile uuid;
begin
  v_club:=coalesce(new.club_id,old.club_id);
  v_profile:=coalesce(new.profile_id,old.profile_id);
  perform public.emit_domain_event(v_club,'UserPermissionOverrideUpdated','permission',null,
    jsonb_build_object('title','Permissão individual atualizada','description','Foi alterada uma exceção individual de acesso.','route','settings','priority','low','profile_id',v_profile));
  return coalesce(new,old);
end; $$;
drop trigger if exists trg_activity_user_permission_overrides on public.user_permission_overrides;
create trigger trg_activity_user_permission_overrides after insert or update or delete on public.user_permission_overrides for each row execute function public.activity_user_permission_trigger_v1();
