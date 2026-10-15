do $$
declare v_def text;
begin
  select pg_get_functiondef('public.bar_operation_v2(uuid,uuid,text,numeric,uuid,numeric,numeric,text,text,boolean,uuid)'::regprocedure) into v_def;
  v_def := replace(
    v_def,
    'where club_id=target_club and active=true and lower(name)=lower(''Club House'') limit 1;' || E'\n      if v_account is null then',
    'where club_id=target_club and active=true and lower(name)=lower(''Caixa'') limit 1;' || E'\n      if v_account is null then'
  );
  execute v_def;
end $$;
