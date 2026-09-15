-- Commit 15 — Hardening global da superfície RPC/Auth da RC1
-- Objetivos:
-- 1) remover execução anónima/por PUBLIC de todas as SECURITY DEFINER públicas;
-- 2) preservar explicitamente a superfície já disponível a authenticated;
-- 3) impedir chamada direta de funções usadas exclusivamente como triggers;
-- 4) manter RPCs server-only do push acessíveis ao service_role;
-- 5) corrigir search_path das funções sinalizadas pelo Security Advisor.

do $$
declare
  fn record;
  sig regprocedure;
  authenticated_api regprocedure[];
begin
  select coalesce(array_agg(p.oid::regprocedure), array[]::regprocedure[])
    into authenticated_api
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef = true
    and has_function_privilege('authenticated', p.oid, 'EXECUTE')
    and not exists (
      select 1
      from pg_trigger t
      where not t.tgisinternal
        and t.tgfoid = p.oid
    );

  -- SECURITY DEFINER nunca deve herdar EXECUTE através de PUBLIC/anon.
  for fn in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef = true
  loop
    execute format(
      'revoke execute on function %s from public, anon',
      fn.signature
    );
  end loop;

  -- Repor de forma explícita apenas a API que já estava disponível a utilizadores
  -- autenticados antes deste hardening. Isto evita regressões funcionais causadas
  -- por privilégios que anteriormente eram herdados de PUBLIC.
  foreach sig in array authenticated_api
  loop
    execute format(
      'grant execute on function %s to authenticated',
      sig
    );
  end loop;

  -- Funções de trigger são implementação interna e não uma RPC pública da app.
  for fn in
    select distinct p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_trigger t on t.tgfoid = p.oid and not t.tgisinternal
    where n.nspname = 'public'
      and p.prosecdef = true
  loop
    execute format(
      'revoke execute on function %s from authenticated',
      fn.signature
    );
  end loop;
end
$$;

-- RPCs chamadas exclusivamente pela Edge Function push-dispatch.
revoke execute on function public.claim_push_delivery_v1(uuid,uuid) from authenticated;
revoke execute on function public.complete_push_delivery_v1(uuid,text,text,text) from authenticated;
revoke execute on function public.deactivate_push_device_server_v1(uuid) from authenticated;
grant execute on function public.claim_push_delivery_v1(uuid,uuid) to service_role;
grant execute on function public.complete_push_delivery_v1(uuid,text,text,text) to service_role;
grant execute on function public.deactivate_push_device_server_v1(uuid) to service_role;

-- Corrigir os dois avisos de search_path mutável atualmente reportados.
alter function public.euromillions_prize_category_v1(integer,integer)
  set search_path = public, pg_temp;
alter function public.module_view_permission(text)
  set search_path = public, pg_temp;

-- Guardas de regressão: se uma migration futura voltar a expor uma
-- SECURITY DEFINER a anon/PUBLIC ou reabrir um trigger a authenticated,
-- esta migration falha em vez de deixar a superfície insegura passar despercebida.
do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef = true
      and has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'Commit 15: ainda existem SECURITY DEFINER executáveis por anon.';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_trigger t on t.tgfoid = p.oid and not t.tgisinternal
    where n.nspname = 'public'
      and p.prosecdef = true
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) then
    raise exception 'Commit 15: ainda existem funções de trigger SECURITY DEFINER executáveis diretamente por authenticated.';
  end if;
end
$$;
