create or replace function public.fee_operational_reference_guard_v1()
returns trigger
language plpgsql
set search_path=public
as $$
declare
  v jsonb:=to_jsonb(new);
  v_id uuid;
  v_member uuid;
  v_payment_member uuid;
  v_obligation_member uuid;
begin
  if nullif(v->>'member_id','') is not null then
    v_member:=(v->>'member_id')::uuid;
    if not exists(select 1 from public.members m where m.id=v_member and m.club_id=new.club_id) then
      raise exception 'O membro não pertence ao clube.';
    end if;
  end if;

  if nullif(v->>'obligation_id','') is not null then
    v_id:=(v->>'obligation_id')::uuid;
    select o.member_id into v_obligation_member
    from public.fee_obligations o
    where o.id=v_id and o.club_id=new.club_id;
    if v_obligation_member is null or (v_member is not null and v_obligation_member<>v_member) then
      raise exception 'A quota não pertence ao membro/clube.';
    end if;
  end if;

  if nullif(v->>'payment_id','') is not null then
    v_id:=(v->>'payment_id')::uuid;
    select p.member_id into v_payment_member
    from public.fee_payments p
    where p.id=v_id and p.club_id=new.club_id;
    if v_payment_member is null or (v_member is not null and v_payment_member<>v_member) then
      raise exception 'O pagamento não pertence ao membro/clube.';
    end if;
  end if;

  if v_payment_member is not null and v_obligation_member is not null and v_payment_member<>v_obligation_member then
    raise exception 'Pagamento e quota pertencem a membros diferentes.';
  end if;

  if nullif(v->>'source_credit_id','') is not null then
    v_id:=(v->>'source_credit_id')::uuid;
    if not exists(select 1 from public.fee_credits c where c.id=v_id and c.club_id=new.club_id and (v_member is null or c.member_id=v_member)) then
      raise exception 'O crédito de origem não pertence ao membro/clube.';
    end if;
  end if;

  if nullif(v->>'fee_payment_id','') is not null then
    v_id:=(v->>'fee_payment_id')::uuid;
    if not exists(select 1 from public.fee_payments p where p.id=v_id and p.club_id=new.club_id and (v_member is null or p.member_id=v_member)) then
      raise exception 'O pagamento validado não pertence ao membro/clube.';
    end if;
  end if;

  if nullif(v->>'transaction_id','') is not null then
    v_id:=(v->>'transaction_id')::uuid;
    if not exists(select 1 from public.treasury_transactions t where t.id=v_id and t.club_id=new.club_id) then
      raise exception 'O movimento financeiro não pertence ao clube.';
    end if;
  end if;

  return new;
end;
$$;
revoke all on function public.fee_operational_reference_guard_v1() from public,anon,authenticated;