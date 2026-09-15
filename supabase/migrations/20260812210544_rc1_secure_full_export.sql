create table public.exports (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  requested_by uuid references public.profiles(id) on delete set null,
  status text not null default 'running' check (status in ('running','completed','failed')),
  modules text[] not null,
  include_sensitive boolean not null default false,
  include_files boolean not null default false,
  manifest_version text not null default 'bob-export-v1',
  dataset_count integer not null default 0 check (dataset_count >= 0),
  row_count integer not null default 0 check (row_count >= 0),
  file_count integer not null default 0 check (file_count >= 0),
  byte_size bigint not null default 0 check (byte_size >= 0),
  error_code text,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create index exports_club_requested_at_idx
  on public.exports (club_id, requested_at desc);
create index exports_requested_by_idx
  on public.exports (requested_by)
  where requested_by is not null;

alter table public.exports enable row level security;

create policy exports_direction_read
on public.exports
for select
to authenticated
using (
  public.has_club_role(
    club_id,
    array['president','vice_president','admin','administrator','super_admin']::text[]
  )
);

revoke all on table public.exports from public, anon, authenticated;
grant select on table public.exports to authenticated;
grant select, insert, update, delete on table public.exports to service_role;

create or replace function public.begin_club_export_v1(
  target_club uuid,
  p_modules text[],
  p_include_sensitive boolean default false,
  p_include_files boolean default false,
  p_manifest_version text default 'bob-export-v1'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_export uuid;
  v_modules text[];
  v_version text := coalesce(nullif(btrim(p_manifest_version), ''), 'bob-export-v1');
  v_allowed constant text[] := array[
    'members','treasury','financial','fees','lottery','events','inventory',
    'documents','communication','agenda','weekly_officer','configuration','audit'
  ]::text[];
begin
  if auth.uid() is null then
    raise exception 'Autenticação necessária.';
  end if;

  if not public.has_club_role(
    target_club,
    array['president','vice_president','admin','administrator','super_admin']::text[]
  ) then
    raise exception 'Sem permissão para exportação integral.';
  end if;

  select array_agg(module_key order by module_key)
    into v_modules
  from (
    select distinct btrim(value) as module_key
    from unnest(coalesce(p_modules, array[]::text[])) as value
    where value is not null and btrim(value) <> ''
  ) normalized;

  if coalesce(cardinality(v_modules), 0) = 0 then
    raise exception 'Seleciona pelo menos uma área para exportar.';
  end if;

  if exists (
    select 1
    from unnest(v_modules) as module_key
    where not (module_key = any(v_allowed))
  ) then
    raise exception 'A exportação contém uma área inválida.';
  end if;

  if length(v_version) > 32 or v_version !~ '^[A-Za-z0-9._-]+$' then
    raise exception 'Versão do manifesto inválida.';
  end if;

  if coalesce(p_include_sensitive, false) and not (
    public.has_club_permission(target_club, 'viewEmergencyData')
    and public.has_club_permission(target_club, 'viewSensitiveDocuments')
  ) then
    raise exception 'Sem permissão para incluir dados altamente sensíveis.';
  end if;

  insert into public.exports (
    club_id, requested_by, status, modules, include_sensitive, include_files,
    manifest_version
  ) values (
    target_club, auth.uid(), 'running', v_modules,
    coalesce(p_include_sensitive, false), coalesce(p_include_files, false),
    v_version
  )
  returning id into v_export;

  insert into public.audit_log (
    club_id, actor_id, action, entity_type, entity_id, after_data, data, created_at
  ) values (
    target_club,
    auth.uid(),
    'club_export_started',
    'club_export',
    v_export::text,
    jsonb_build_object(
      'status', 'running',
      'modules', to_jsonb(v_modules),
      'include_sensitive', coalesce(p_include_sensitive, false),
      'include_files', coalesce(p_include_files, false),
      'manifest_version', v_version
    ),
    jsonb_build_object('export_id', v_export),
    now()
  );

  return v_export;
end;
$$;

create or replace function public.complete_club_export_v1(
  target_club uuid,
  p_export uuid,
  p_dataset_count integer,
  p_row_count integer,
  p_file_count integer,
  p_byte_size bigint
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.exports%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Autenticação necessária.';
  end if;

  if not public.has_club_role(
    target_club,
    array['president','vice_president','admin','administrator','super_admin']::text[]
  ) then
    raise exception 'Sem permissão para exportação integral.';
  end if;

  if coalesce(p_dataset_count, -1) < 0
     or coalesce(p_row_count, -1) < 0
     or coalesce(p_file_count, -1) < 0
     or coalesce(p_byte_size, -1) < 0 then
    raise exception 'Métricas de exportação inválidas.';
  end if;

  select * into v_row
  from public.exports
  where id = p_export
    and club_id = target_club
    and requested_by = auth.uid()
  for update;

  if not found then
    raise exception 'Exportação não encontrada.';
  end if;
  if v_row.status <> 'running' then
    raise exception 'A exportação já foi finalizada.';
  end if;

  update public.exports
  set status = 'completed',
      dataset_count = p_dataset_count,
      row_count = p_row_count,
      file_count = p_file_count,
      byte_size = p_byte_size,
      error_code = null,
      completed_at = now()
  where id = p_export;

  insert into public.audit_log (
    club_id, actor_id, action, entity_type, entity_id, after_data, data, created_at
  ) values (
    target_club,
    auth.uid(),
    'club_export_completed',
    'club_export',
    p_export::text,
    jsonb_build_object(
      'status', 'completed',
      'dataset_count', p_dataset_count,
      'row_count', p_row_count,
      'file_count', p_file_count,
      'byte_size', p_byte_size
    ),
    jsonb_build_object('export_id', p_export),
    now()
  );
end;
$$;

create or replace function public.fail_club_export_v1(
  target_club uuid,
  p_export uuid,
  p_error_code text default 'generation_failed'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.exports%rowtype;
  v_code text := left(
    regexp_replace(
      lower(coalesce(nullif(btrim(p_error_code), ''), 'generation_failed')),
      '[^a-z0-9._-]+', '_', 'g'
    ),
    80
  );
begin
  if auth.uid() is null then
    raise exception 'Autenticação necessária.';
  end if;

  if not public.has_club_role(
    target_club,
    array['president','vice_president','admin','administrator','super_admin']::text[]
  ) then
    raise exception 'Sem permissão para exportação integral.';
  end if;

  select * into v_row
  from public.exports
  where id = p_export
    and club_id = target_club
    and requested_by = auth.uid()
  for update;

  if not found then
    raise exception 'Exportação não encontrada.';
  end if;
  if v_row.status <> 'running' then
    return;
  end if;

  update public.exports
  set status = 'failed',
      error_code = v_code,
      completed_at = now()
  where id = p_export;

  insert into public.audit_log (
    club_id, actor_id, action, entity_type, entity_id, after_data, data, created_at
  ) values (
    target_club,
    auth.uid(),
    'club_export_failed',
    'club_export',
    p_export::text,
    jsonb_build_object('status', 'failed', 'error_code', v_code),
    jsonb_build_object('export_id', p_export),
    now()
  );
end;
$$;

revoke all on function public.begin_club_export_v1(uuid,text[],boolean,boolean,text) from public, anon;
revoke all on function public.complete_club_export_v1(uuid,uuid,integer,integer,integer,bigint) from public, anon;
revoke all on function public.fail_club_export_v1(uuid,uuid,text) from public, anon;

grant execute on function public.begin_club_export_v1(uuid,text[],boolean,boolean,text) to authenticated, service_role;
grant execute on function public.complete_club_export_v1(uuid,uuid,integer,integer,integer,bigint) to authenticated, service_role;
grant execute on function public.fail_club_export_v1(uuid,uuid,text) to authenticated, service_role;
