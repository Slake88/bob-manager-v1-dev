-- Participação da gestão: só agregados, independente dos resultados por opção.
create or replace function public.poll_participation_v1(
  target_club uuid,
  p_poll uuid
)
returns table (
  eligible_count bigint,
  voted_count bigint,
  remaining_count bigint,
  participation_percent numeric
)
language plpgsql
stable
security definer
set search_path = 'public'
as $$
begin
  if auth.uid() is null
     or not public.has_club_permission(target_club, 'manageCommunication') then
    raise exception 'Sem autorização para consultar a participação.';
  end if;

  if not exists (
    select 1 from public.polls p
    where p.id = p_poll and p.club_id = target_club
  ) then
    raise exception 'Votação não encontrada.';
  end if;

  return query
  -- O eleitorado é o atualmente elegível. A regra autoritativa permanece
  -- na função existente; alterações de elegibilidade não apagam votos.
  with eligible as materialized (
    select distinct cm.profile_id
    from public.club_memberships cm
    where cm.club_id = target_club
      and public.poll_member_eligible_internal_v1(target_club, cm.profile_id)
  ), totals as (
    select
      (select count(*) from eligible) as eligible_total,
      (
        select count(distinct v.profile_id)
        from public.poll_votes v
        join eligible e on e.profile_id = v.profile_id
        where v.club_id = target_club and v.poll_id = p_poll
      ) as voted_total
  )
  -- Uma pessoa com várias seleções conta uma vez. Não há identificadores
  -- nem resultados por opção na resposta, mesmo em votações identificadas.
  select
    t.eligible_total,
    t.voted_total,
    greatest(t.eligible_total - t.voted_total, 0::bigint),
    case when t.eligible_total = 0 then 0::numeric
      else t.voted_total::numeric / t.eligible_total::numeric * 100
    end
  from totals t;
end;
$$;

revoke all on function public.poll_participation_v1(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.poll_participation_v1(uuid, uuid)
  to authenticated;
