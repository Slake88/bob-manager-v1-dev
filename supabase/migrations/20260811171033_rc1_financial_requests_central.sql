
-- Commit 8: Central de pedidos, cobranças e pagamentos.

create table if not exists public.financial_requests (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete restrict,
  request_type text not null check (request_type in ('reimbursement','charge')),
  category text not null check (category in ('reimbursement','fee','euromillions','bar','other')),
  batch_id uuid,
  amount numeric(12,2) not null check (amount > 0),
  description text not null,
  due_date date,
  status text not null check (status in (
    'draft','pending_review','needs_info','approved',
    'awaiting_payment','awaiting_validation','rejected','paid','cancelled'
  )),
  review_note text,
  payment_method text,
  treasury_account_id uuid references public.treasury_accounts(id) on delete set null,
  treasury_transaction_id uuid references public.treasury_transactions(id) on delete set null,
  requested_by uuid references public.profiles(id) on delete set null,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  submitted_at timestamptz,
  paid_at timestamptz,
  paid_by uuid references public.profiles(id) on delete set null,
  source_type text,
  source_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null
);

create index if not exists financial_requests_club_status_idx
  on public.financial_requests(club_id,status,created_at desc);
create index if not exists financial_requests_member_idx
  on public.financial_requests(member_id,created_at desc);
create index if not exists financial_requests_batch_idx
  on public.financial_requests(batch_id) where batch_id is not null;
create unique index if not exists financial_requests_transaction_uidx
  on public.financial_requests(treasury_transaction_id) where treasury_transaction_id is not null;

create table if not exists public.financial_request_attachments (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  request_id uuid not null references public.financial_requests(id) on delete cascade,
  kind text not null check (kind in ('receipt','member_payment_proof','club_payment_proof','other')),
  storage_path text not null,
  original_file_name text not null,
  mime_type text,
  file_size bigint not null default 0 check (file_size >= 0 and file_size <= 20971520),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  unique(request_id,storage_path)
);

create index if not exists financial_request_attachments_request_idx
  on public.financial_request_attachments(request_id,created_at);

drop trigger if exists financial_requests_audit_stamp on public.financial_requests;
create trigger financial_requests_audit_stamp
before insert or update on public.financial_requests
for each row execute function public.audit_stamp_row_v1();

drop trigger if exists financial_requests_audit_capture on public.financial_requests;
create trigger financial_requests_audit_capture
after insert or update or delete on public.financial_requests
for each row execute function public.audit_capture_row_v1();

drop trigger if exists financial_request_attachments_audit_stamp on public.financial_request_attachments;
create trigger financial_request_attachments_audit_stamp
before insert or update on public.financial_request_attachments
for each row execute function public.audit_stamp_row_v1();

drop trigger if exists financial_request_attachments_audit_capture on public.financial_request_attachments;
create trigger financial_request_attachments_audit_capture
after insert or update or delete on public.financial_request_attachments
for each row execute function public.audit_capture_row_v1();

create or replace function public.financial_manager_v1(target_club uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select auth.uid() is not null
     and public.has_club_permission(target_club,'approveExpenseRequests');
$$;

create or replace function public.current_financial_member_v1(target_club uuid)
returns uuid
language sql
stable
security definer
set search_path=public
as $$
  select m.id
  from public.members m
  where m.club_id=target_club
    and m.profile_id=auth.uid()
    and m.status::text not in ('former','deceased')
  order by m.created_at
  limit 1;
$$;

create or replace function public.financial_request_access_v1(p_request uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists (
    select 1
    from public.financial_requests r
    join public.members m on m.id=r.member_id
    where r.id=p_request
      and (
        public.financial_manager_v1(r.club_id)
        or m.profile_id=auth.uid()
      )
  );
$$;

create or replace function public.financial_activity_v1(
  target_club uuid,
  p_request uuid,
  p_title text,
  p_description text
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  insert into public.activity_feed(
    club_id,actor_id,activity_type,title,description,entity_type,entity_id,metadata
  ) values (
    target_club,auth.uid(),'treasury',p_title,p_description,
    'financial_request',p_request,
    jsonb_build_object('module_code','treasury','request_id',p_request)
  );
end;
$$;

create or replace function public.notify_financial_profile_v1(
  target_club uuid,
  p_profile uuid,
  p_request uuid,
  p_title text,
  p_body text,
  p_priority text default 'normal'
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if p_profile is null then return; end if;
  if not exists(
    select 1 from public.club_memberships cm
    where cm.club_id=target_club and cm.profile_id=p_profile and cm.active=true
  ) then return; end if;

  if coalesce((
    select np.in_app_enabled from public.notification_preferences np
    where np.club_id=target_club and np.profile_id=p_profile and np.module_code='treasury'
  ),true) then
    insert into public.notifications(
      club_id,profile_id,title,body,notification_type,module_code,priority,
      entity_type,entity_id,action_route,metadata
    ) values (
      target_club,p_profile,p_title,p_body,'financial_request','treasury',
      case when p_priority in ('low','normal','high','urgent') then p_priority else 'normal' end,
      'financial_request',p_request,'/financial',
      jsonb_build_object('request_id',p_request)
    );
  end if;
end;
$$;

create or replace function public.notify_financial_managers_v1(
  target_club uuid,
  p_request uuid,
  p_title text,
  p_body text,
  p_priority text default 'normal'
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare r record;
begin
  for r in
    select cm.profile_id
    from public.club_memberships cm
    where cm.club_id=target_club
      and cm.active=true
      and public.profile_has_club_permission(target_club,cm.profile_id,'approveExpenseRequests')
  loop
    perform public.notify_financial_profile_v1(
      target_club,r.profile_id,p_request,p_title,p_body,p_priority
    );
  end loop;
end;
$$;

create or replace function public.create_reimbursement_draft_v1(
  target_club uuid,
  p_member uuid,
  p_amount numeric,
  p_description text
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_member uuid; v_request uuid; v_own uuid;
begin
  if not public.has_club_access(target_club) then raise exception 'Sem acesso ao clube.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'O valor deve ser superior a zero.'; end if;
  if nullif(btrim(p_description),'') is null then raise exception 'A descrição é obrigatória.'; end if;

  v_own:=public.current_financial_member_v1(target_club);
  if public.financial_manager_v1(target_club) and p_member is not null then
    v_member:=p_member;
  else
    v_member:=v_own;
    if p_member is not null and p_member is distinct from v_own then
      raise exception 'Só podes criar pedidos para o teu próprio perfil.';
    end if;
  end if;

  if v_member is null then
    raise exception 'O utilizador não está associado a um membro do clube.';
  end if;
  if not exists(
    select 1 from public.members m
    where m.id=v_member and m.club_id=target_club
      and m.status::text not in ('former','deceased')
  ) then raise exception 'Membro inválido para este pedido.'; end if;

  insert into public.financial_requests(
    club_id,member_id,request_type,category,amount,description,status,requested_by
  ) values (
    target_club,v_member,'reimbursement','reimbursement',
    round(p_amount,2),btrim(p_description),'draft',auth.uid()
  ) returning id into v_request;

  return v_request;
end;
$$;

create or replace function public.update_reimbursement_draft_v1(
  target_club uuid,
  p_request uuid,
  p_amount numeric,
  p_description text
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare r public.financial_requests%rowtype; own_member uuid;
begin
  if p_amount is null or p_amount<=0 then raise exception 'O valor deve ser superior a zero.'; end if;
  if nullif(btrim(p_description),'') is null then raise exception 'A descrição é obrigatória.'; end if;

  select * into r from public.financial_requests
  where id=p_request and club_id=target_club for update;
  if not found or r.request_type<>'reimbursement' then raise exception 'Pedido não encontrado.'; end if;
  if r.status not in ('draft','needs_info') then raise exception 'Este pedido já não pode ser editado.'; end if;

  own_member:=public.current_financial_member_v1(target_club);
  if not public.financial_manager_v1(target_club) and r.member_id is distinct from own_member then
    raise exception 'Sem autorização.';
  end if;

  update public.financial_requests
  set amount=round(p_amount,2),description=btrim(p_description),review_note=null
  where id=p_request;
end;
$$;

create or replace function public.add_financial_attachment_v1(
  target_club uuid,
  p_request uuid,
  p_kind text,
  p_storage_path text,
  p_original_file_name text,
  p_mime_type text,
  p_file_size bigint
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare r public.financial_requests%rowtype; v_id uuid; own_member uuid; manager boolean;
begin
  select * into r from public.financial_requests
  where id=p_request and club_id=target_club;
  if not found then raise exception 'Pedido não encontrado.'; end if;
  manager:=public.financial_manager_v1(target_club);
  own_member:=public.current_financial_member_v1(target_club);

  if not manager and r.member_id is distinct from own_member then raise exception 'Sem autorização.'; end if;
  if p_kind not in ('receipt','member_payment_proof','club_payment_proof','other') then
    raise exception 'Tipo de anexo inválido.';
  end if;
  if p_file_size is null or p_file_size<=0 or p_file_size>20971520 then
    raise exception 'O ficheiro deve ter entre 1 byte e 20 MB.';
  end if;
  if p_storage_path not like target_club::text||'/'||p_request::text||'/%' then
    raise exception 'Caminho de armazenamento inválido.';
  end if;

  if p_kind='receipt' then
    if r.request_type<>'reimbursement' or r.status not in ('draft','needs_info') then
      raise exception 'Não é possível adicionar talões neste estado.';
    end if;
  elsif p_kind='member_payment_proof' then
    if r.request_type<>'charge' or r.status<>'awaiting_payment' or r.member_id is distinct from own_member then
      raise exception 'Não é possível adicionar este comprovativo.';
    end if;
  elsif p_kind='club_payment_proof' then
    if r.request_type<>'reimbursement' or r.status<>'approved' or not manager then
      raise exception 'O comprovativo de pagamento só pode ser anexado após aprovação.';
    end if;
  elsif r.status in ('paid','rejected','cancelled') then
    raise exception 'O processo está encerrado.';
  end if;

  insert into public.financial_request_attachments(
    club_id,request_id,kind,storage_path,original_file_name,mime_type,file_size
  ) values (
    target_club,p_request,p_kind,p_storage_path,
    coalesce(nullif(btrim(p_original_file_name),''),'ficheiro'),
    nullif(btrim(coalesce(p_mime_type,'')),''),
    p_file_size
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.submit_reimbursement_v1(
  target_club uuid,
  p_request uuid
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare r public.financial_requests%rowtype; own_member uuid; member_name text;
begin
  select * into r from public.financial_requests
  where id=p_request and club_id=target_club for update;
  if not found or r.request_type<>'reimbursement' then raise exception 'Pedido não encontrado.'; end if;
  if r.status not in ('draft','needs_info') then raise exception 'Este pedido não pode ser submetido.'; end if;

  own_member:=public.current_financial_member_v1(target_club);
  if not public.financial_manager_v1(target_club) and r.member_id is distinct from own_member then
    raise exception 'Sem autorização.';
  end if;
  if not exists(
    select 1 from public.financial_request_attachments a
    where a.request_id=p_request and a.kind='receipt'
  ) then raise exception 'Adiciona pelo menos um talão ou recibo.'; end if;

  update public.financial_requests
  set status='pending_review',submitted_at=now(),review_note=null
  where id=p_request;

  select coalesce(nullif(m.nickname,''),m.full_name) into member_name
  from public.members m where m.id=r.member_id;

  perform public.financial_activity_v1(
    target_club,p_request,'Pedido de reembolso submetido',
    coalesce(member_name,'Membro')||' submeteu um pedido de '||to_char(r.amount,'FM999999990.00')||' €.'
  );
  perform public.notify_financial_managers_v1(
    target_club,p_request,'Novo pedido de reembolso',
    coalesce(member_name,'Membro')||' pediu reembolso de '||to_char(r.amount,'FM999999990.00')||' €.',
    'high'
  );
end;
$$;

create or replace function public.review_reimbursement_v1(
  target_club uuid,
  p_request uuid,
  p_action text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare r public.financial_requests%rowtype; member_profile uuid; next_status text; title text; body text;
begin
  if not public.financial_manager_v1(target_club) then raise exception 'Sem autorização.'; end if;
  select * into r from public.financial_requests
  where id=p_request and club_id=target_club for update;
  if not found or r.request_type<>'reimbursement' or r.status<>'pending_review' then
    raise exception 'Pedido não está pendente de análise.';
  end if;

  if p_action='approve' then
    next_status:='approved'; title:='Reembolso aprovado'; body:='O teu pedido foi aprovado e aguarda pagamento.';
  elsif p_action='reject' then
    if nullif(btrim(coalesce(p_note,'')),'') is null then raise exception 'Indica o motivo da rejeição.'; end if;
    next_status:='rejected'; title:='Reembolso rejeitado'; body:='O teu pedido foi rejeitado: '||btrim(p_note);
  elsif p_action='request_info' then
    if nullif(btrim(coalesce(p_note,'')),'') is null then raise exception 'Indica a informação em falta.'; end if;
    next_status:='needs_info'; title:='Reembolso precisa de informação'; body:=btrim(p_note);
  else
    raise exception 'Ação inválida.';
  end if;

  update public.financial_requests
  set status=next_status,review_note=nullif(btrim(coalesce(p_note,'')),''),
      reviewed_by=auth.uid(),reviewed_at=now()
  where id=p_request;

  select m.profile_id into member_profile from public.members m where m.id=r.member_id;
  perform public.notify_financial_profile_v1(target_club,member_profile,p_request,title,body,
    case when p_action='request_info' then 'high' else 'normal' end);
  perform public.financial_activity_v1(target_club,p_request,title,body);
end;
$$;

create or replace function public.pay_reimbursement_v1(
  target_club uuid,
  p_request uuid,
  p_account uuid,
  p_payment_method text,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare r public.financial_requests%rowtype; tx uuid; member_profile uuid; member_name text; method text;
begin
  if not public.financial_manager_v1(target_club) then raise exception 'Sem autorização.'; end if;
  method:=lower(btrim(coalesce(p_payment_method,'')));
  if method not in ('cash','mbway','bank_transfer','other') then raise exception 'Método de pagamento inválido.'; end if;

  select * into r from public.financial_requests
  where id=p_request and club_id=target_club for update;
  if not found or r.request_type<>'reimbursement' or r.status<>'approved' then
    raise exception 'O reembolso não está aprovado para pagamento.';
  end if;
  if not exists(select 1 from public.treasury_accounts a where a.id=p_account and a.club_id=target_club and a.active=true) then
    raise exception 'Conta financeira inválida.';
  end if;
  if method<>'cash' and not exists(
    select 1 from public.financial_request_attachments a
    where a.request_id=p_request and a.kind='club_payment_proof'
  ) then
    raise exception 'Anexa o comprovativo do pagamento antes de liquidar.';
  end if;

  select m.profile_id,coalesce(nullif(m.nickname,''),m.full_name)
  into member_profile,member_name from public.members m where m.id=r.member_id;

  insert into public.treasury_transactions(
    club_id,kind,account_id,transaction_date,description,amount,payment_method,
    notes,source_type,source_id,created_by
  ) values (
    target_club,'expense',p_account,current_date,
    'Reembolso - '||coalesce(member_name,'Membro')||' - '||r.description,
    r.amount,method,nullif(btrim(coalesce(p_note,'')),''),
    'financial_reimbursement',p_request,auth.uid()
  ) returning id into tx;

  update public.financial_requests
  set status='paid',payment_method=method,treasury_account_id=p_account,
      treasury_transaction_id=tx,paid_at=now(),paid_by=auth.uid()
  where id=p_request;

  perform public.notify_financial_profile_v1(
    target_club,member_profile,p_request,'Reembolso liquidado',
    'O reembolso de '||to_char(r.amount,'FM999999990.00')||' € foi liquidado.','normal'
  );
  perform public.financial_activity_v1(
    target_club,p_request,'Reembolso liquidado',
    coalesce(member_name,'Membro')||' · '||to_char(r.amount,'FM999999990.00')||' €'
  );
  return tx;
end;
$$;

create or replace function public.create_member_charges_v1(
  target_club uuid,
  p_member_ids uuid[],
  p_category text,
  p_amount numeric,
  p_description text,
  p_due_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_batch uuid:=gen_random_uuid(); v_member uuid; v_request uuid; n integer:=0; member_profile uuid; member_name text; ids jsonb:='[]'::jsonb;
begin
  if not public.financial_manager_v1(target_club) then raise exception 'Sem autorização para criar cobranças.'; end if;
  if p_category not in ('fee','euromillions','bar','other') then raise exception 'Tipo de cobrança inválido.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'O valor deve ser superior a zero.'; end if;
  if nullif(btrim(p_description),'') is null then raise exception 'A descrição é obrigatória.'; end if;
  if coalesce(array_length(p_member_ids,1),0)=0 then raise exception 'Seleciona pelo menos um membro.'; end if;

  for v_member in select distinct unnest(p_member_ids)
  loop
    select m.profile_id,coalesce(nullif(m.nickname,''),m.full_name)
      into member_profile,member_name
    from public.members m
    where m.id=v_member and m.club_id=target_club
      and m.status::text in ('active','prospect','full_color','honorary');
    if not found then raise exception 'Existe um membro não elegível na seleção.'; end if;

    insert into public.financial_requests(
      club_id,member_id,request_type,category,batch_id,amount,description,due_date,
      status,requested_by
    ) values (
      target_club,v_member,'charge',p_category,v_batch,round(p_amount,2),
      btrim(p_description),p_due_date,'awaiting_payment',auth.uid()
    ) returning id into v_request;

    n:=n+1;
    ids:=ids||to_jsonb(v_request);
    perform public.notify_financial_profile_v1(
      target_club,member_profile,v_request,'Nova cobrança',
      btrim(p_description)||' · '||to_char(p_amount,'FM999999990.00')||' €',
      'high'
    );
  end loop;

  perform public.financial_activity_v1(
    target_club,null,'Cobranças emitidas',
    n||' cobrança(s) de '||to_char(p_amount,'FM999999990.00')||' € · '||btrim(p_description)
  );

  return jsonb_build_object('batch_id',v_batch,'count',n,'request_ids',ids);
end;
$$;

create or replace function public.submit_charge_proof_v1(
  target_club uuid,
  p_request uuid
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare r public.financial_requests%rowtype; own_member uuid; member_name text;
begin
  select * into r from public.financial_requests
  where id=p_request and club_id=target_club for update;
  if not found or r.request_type<>'charge' or r.status<>'awaiting_payment' then
    raise exception 'Cobrança não está disponível para envio de comprovativo.';
  end if;
  own_member:=public.current_financial_member_v1(target_club);
  if r.member_id is distinct from own_member then raise exception 'Sem autorização.'; end if;
  if not exists(
    select 1 from public.financial_request_attachments a
    where a.request_id=p_request and a.kind='member_payment_proof'
  ) then raise exception 'Anexa o comprovativo de pagamento.'; end if;

  update public.financial_requests
  set status='awaiting_validation',submitted_at=now(),review_note=null
  where id=p_request;

  select coalesce(nullif(m.nickname,''),m.full_name) into member_name from public.members m where m.id=r.member_id;
  perform public.notify_financial_managers_v1(
    target_club,p_request,'Pagamento para validar',
    coalesce(member_name,'Membro')||' enviou comprovativo de '||to_char(r.amount,'FM999999990.00')||' €.',
    'high'
  );
  perform public.financial_activity_v1(
    target_club,p_request,'Comprovativo submetido',
    coalesce(member_name,'Membro')||' · '||to_char(r.amount,'FM999999990.00')||' €'
  );
end;
$$;

create or replace function public.review_charge_payment_v1(
  target_club uuid,
  p_request uuid,
  p_action text,
  p_account uuid default null,
  p_payment_method text default null,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare r public.financial_requests%rowtype; member_profile uuid; member_name text; method text; tx uuid;
begin
  if not public.financial_manager_v1(target_club) then raise exception 'Sem autorização.'; end if;
  select * into r from public.financial_requests
  where id=p_request and club_id=target_club for update;
  if not found or r.request_type<>'charge' then raise exception 'Cobrança não encontrada.'; end if;

  select m.profile_id,coalesce(nullif(m.nickname,''),m.full_name)
  into member_profile,member_name from public.members m where m.id=r.member_id;

  if p_action='reject' then
    if r.status<>'awaiting_validation' then raise exception 'Não existe comprovativo pendente de validação.'; end if;
    if nullif(btrim(coalesce(p_note,'')),'') is null then raise exception 'Indica o motivo da rejeição.'; end if;
    update public.financial_requests
    set status='awaiting_payment',review_note=btrim(p_note),reviewed_by=auth.uid(),reviewed_at=now()
    where id=p_request;
    perform public.notify_financial_profile_v1(
      target_club,member_profile,p_request,'Comprovativo não aceite',
      btrim(p_note),'high'
    );
    perform public.financial_activity_v1(target_club,p_request,'Comprovativo rejeitado',btrim(p_note));
    return null;
  elsif p_action<>'approve' then
    raise exception 'Ação inválida.';
  end if;

  method:=lower(btrim(coalesce(p_payment_method,'')));
  if method not in ('cash','mbway','bank_transfer','other') then raise exception 'Método de pagamento inválido.'; end if;
  if p_account is null or not exists(
    select 1 from public.treasury_accounts a
    where a.id=p_account and a.club_id=target_club and a.active=true
  ) then raise exception 'Conta financeira inválida.'; end if;

  if method='cash' then
    if r.status not in ('awaiting_payment','awaiting_validation') then raise exception 'Cobrança não está pendente.'; end if;
  else
    if r.status<>'awaiting_validation' then raise exception 'O comprovativo ainda não foi submetido.'; end if;
    if not exists(
      select 1 from public.financial_request_attachments a
      where a.request_id=p_request and a.kind='member_payment_proof'
    ) then raise exception 'Não existe comprovativo anexado.'; end if;
  end if;

  insert into public.treasury_transactions(
    club_id,kind,account_id,transaction_date,description,amount,payment_method,
    notes,source_type,source_id,created_by
  ) values (
    target_club,'income',p_account,current_date,
    'Cobrança - '||coalesce(member_name,'Membro')||' - '||r.description,
    r.amount,method,nullif(btrim(coalesce(p_note,'')),''),
    'financial_charge',p_request,auth.uid()
  ) returning id into tx;

  update public.financial_requests
  set status='paid',payment_method=method,treasury_account_id=p_account,
      treasury_transaction_id=tx,review_note=null,reviewed_by=auth.uid(),reviewed_at=now(),
      paid_at=now(),paid_by=auth.uid()
  where id=p_request;

  perform public.notify_financial_profile_v1(
    target_club,member_profile,p_request,'Pagamento validado',
    'Pagamento de '||to_char(r.amount,'FM999999990.00')||' € confirmado.','normal'
  );
  perform public.financial_activity_v1(
    target_club,p_request,'Cobrança liquidada',
    coalesce(member_name,'Membro')||' · '||to_char(r.amount,'FM999999990.00')||' €'
  );
  return tx;
end;
$$;

alter table public.financial_requests enable row level security;
alter table public.financial_request_attachments enable row level security;

drop policy if exists financial_requests_read on public.financial_requests;
create policy financial_requests_read on public.financial_requests
for select to authenticated
using (
  public.financial_manager_v1(club_id)
  or exists(
    select 1 from public.members m
    where m.id=member_id and m.profile_id=auth.uid()
  )
);

drop policy if exists financial_attachments_read on public.financial_request_attachments;
create policy financial_attachments_read on public.financial_request_attachments
for select to authenticated
using (public.financial_request_access_v1(request_id));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'financial-documents','financial-documents',false,20971520,
  array['application/pdf','image/jpeg','image/png','image/webp']::text[]
)
on conflict(id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists financial_documents_select on storage.objects;
create policy financial_documents_select on storage.objects
for select to authenticated
using (
  bucket_id='financial-documents'
  and array_length(storage.foldername(name),1)>=2
  and public.financial_request_access_v1((storage.foldername(name))[2]::uuid)
);

drop policy if exists financial_documents_insert on storage.objects;
create policy financial_documents_insert on storage.objects
for insert to authenticated
with check (
  bucket_id='financial-documents'
  and array_length(storage.foldername(name),1)>=2
  and public.financial_request_access_v1((storage.foldername(name))[2]::uuid)
);

drop policy if exists financial_documents_delete on storage.objects;
create policy financial_documents_delete on storage.objects
for delete to authenticated
using (
  bucket_id='financial-documents'
  and array_length(storage.foldername(name),1)>=2
  and public.financial_request_access_v1((storage.foldername(name))[2]::uuid)
);

create or replace function public.dashboard_summary_rc1(target_club uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  can_financial boolean;
  can_approve boolean;
  result jsonb;
  members_count integer:=0;
  prospects_count integer:=0;
  outstanding numeric:=0;
  overdue_count integer:=0;
  open_events_count integer:=0;
  low_stock_count integer:=0;
  expiring_documents_count integer:=0;
  unread_announcements_count integer:=0;
  pending_approvals_count integer:=0;
  total_balance numeric:=0;
  monthly_income numeric:=0;
  monthly_expense numeric:=0;
begin
  if not public.has_club_access(target_club) then raise exception 'Sem acesso ao clube.'; end if;
  can_financial:=public.has_club_permission(target_club,'viewTreasury');
  can_approve:=public.financial_manager_v1(target_club);

  select count(*) filter(where status::text not in ('former','deceased')),
         count(*) filter(where status::text='prospect')
  into members_count,prospects_count
  from public.members where club_id=target_club;

  select coalesce(sum(greatest(amount-paid_amount,0)),0),
         count(*) filter(where greatest(amount-paid_amount,0)>0 and due_date<current_date)
  into outstanding,overdue_count
  from public.fee_obligations where club_id=target_club;

  select count(*) into open_events_count
  from public.events where club_id=target_club and status::text not in ('completed','cancelled','archived');

  select count(*) into low_stock_count
  from public.products
  where club_id=target_club and active=true and (current_stock-reserved_stock)<=minimum_stock;

  select count(*) into expiring_documents_count
  from public.documents where club_id=target_club and expires_at between current_date and current_date+30;

  select count(*) into unread_announcements_count
  from public.announcements a
  where a.club_id=target_club and a.requires_acknowledgement=true and a.published_at<=now()
    and (a.expires_at is null or a.expires_at>now())
    and not exists(
      select 1 from public.announcement_acknowledgements aa
      where aa.announcement_id=a.id and aa.profile_id=auth.uid()
    );

  if can_approve then
    select count(*) into pending_approvals_count
    from public.financial_requests
    where club_id=target_club and status in ('pending_review','awaiting_validation');
  end if;

  if can_financial then
    select coalesce(sum(
      a.opening_balance
      +coalesce((select sum(case when t.kind::text='income' then t.amount when t.kind::text in ('expense','transfer') then -t.amount else 0 end)
                 from public.treasury_transactions t where t.club_id=target_club and t.account_id=a.id),0)
      +coalesce((select sum(t.amount) from public.treasury_transactions t
                 where t.club_id=target_club and t.kind::text='transfer' and t.destination_account_id=a.id),0)
    ),0)
    into total_balance
    from public.treasury_accounts a
    where a.club_id=target_club and a.active=true;

    select coalesce(sum(amount) filter(where kind::text='income'),0),
           coalesce(sum(amount) filter(where kind::text='expense'),0)
    into monthly_income,monthly_expense
    from public.treasury_transactions
    where club_id=target_club
      and date_trunc('month',transaction_date::timestamp)=date_trunc('month',current_date::timestamp);
  end if;

  result:=jsonb_build_object(
    'members',members_count,
    'prospects',prospects_count,
    'total_balance',case when can_financial then total_balance else 0 end,
    'fee_outstanding',outstanding,
    'overdue_fees',overdue_count,
    'open_events',open_events_count,
    'low_stock',low_stock_count,
    'expiring_documents',expiring_documents_count,
    'unread_announcements',unread_announcements_count,
    'pending_approvals',pending_approvals_count,
    'monthly_income',case when can_financial then monthly_income else 0 end,
    'monthly_expense',case when can_financial then monthly_expense else 0 end,
    'can_view_financial',can_financial
  );
  return result;
end;
$$;

-- RPCs expostos apenas a utilizadores autenticados.
revoke all on function public.financial_manager_v1(uuid) from public,anon;
revoke all on function public.current_financial_member_v1(uuid) from public,anon;
revoke all on function public.financial_request_access_v1(uuid) from public,anon;
grant execute on function public.financial_manager_v1(uuid) to authenticated;
grant execute on function public.current_financial_member_v1(uuid) to authenticated;
grant execute on function public.financial_request_access_v1(uuid) to authenticated;

revoke all on function public.financial_activity_v1(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.notify_financial_profile_v1(uuid,uuid,uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.notify_financial_managers_v1(uuid,uuid,text,text,text) from public,anon,authenticated;

revoke all on function public.create_reimbursement_draft_v1(uuid,uuid,numeric,text) from public,anon;
grant execute on function public.create_reimbursement_draft_v1(uuid,uuid,numeric,text) to authenticated;
revoke all on function public.update_reimbursement_draft_v1(uuid,uuid,numeric,text) from public,anon;
grant execute on function public.update_reimbursement_draft_v1(uuid,uuid,numeric,text) to authenticated;
revoke all on function public.add_financial_attachment_v1(uuid,uuid,text,text,text,text,bigint) from public,anon;
grant execute on function public.add_financial_attachment_v1(uuid,uuid,text,text,text,text,bigint) to authenticated;
revoke all on function public.submit_reimbursement_v1(uuid,uuid) from public,anon;
grant execute on function public.submit_reimbursement_v1(uuid,uuid) to authenticated;
revoke all on function public.review_reimbursement_v1(uuid,uuid,text,text) from public,anon;
grant execute on function public.review_reimbursement_v1(uuid,uuid,text,text) to authenticated;
revoke all on function public.pay_reimbursement_v1(uuid,uuid,uuid,text,text) from public,anon;
grant execute on function public.pay_reimbursement_v1(uuid,uuid,uuid,text,text) to authenticated;
revoke all on function public.create_member_charges_v1(uuid,uuid[],text,numeric,text,date) from public,anon;
grant execute on function public.create_member_charges_v1(uuid,uuid[],text,numeric,text,date) to authenticated;
revoke all on function public.submit_charge_proof_v1(uuid,uuid) from public,anon;
grant execute on function public.submit_charge_proof_v1(uuid,uuid) to authenticated;
revoke all on function public.review_charge_payment_v1(uuid,uuid,text,uuid,text,text) from public,anon;
grant execute on function public.review_charge_payment_v1(uuid,uuid,text,uuid,text,text) to authenticated;

revoke all on function public.dashboard_summary_rc1(uuid) from public,anon;
grant execute on function public.dashboard_summary_rc1(uuid) to authenticated;
