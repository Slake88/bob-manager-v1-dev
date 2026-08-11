from pathlib import Path

ROOT = Path.cwd()
repo = ROOT / 'apps/mobile/lib/repositories/activity_repository.dart'
screen = ROOT / 'apps/mobile/lib/screens/activity_screen.dart'
migration = ROOT / 'supabase/migrations/20260811161353_rc1_audit_ui_portugal.sql'

if not repo.exists() or not screen.exists():
    raise SystemExit('ERRO: executa este script na raiz de BOB_Manager_v1_0_DEV.')

sql = r'''-- Commit 5, parte 2 — apresentação de auditoria com hora oficial de Portugal.
create or replace function public.activity_feed_portugal_v1(
  target_club uuid,
  p_module text default null,
  p_limit integer default 100
)
returns table (
  id uuid,
  activity_type text,
  title text,
  description text,
  entity_type text,
  entity_id uuid,
  metadata jsonb,
  created_at timestamptz,
  actor_name text,
  portugal_date text,
  portugal_time text
)
language plpgsql
stable
security invoker
set search_path = 'public'
as $$
begin
  if auth.uid() is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.';
  end if;

  return query
  select
    a.id, a.activity_type, a.title, a.description, a.entity_type, a.entity_id,
    a.metadata, a.created_at, coalesce(p.full_name, 'Sistema')::text,
    to_char(a.created_at at time zone 'Europe/Lisbon', 'DD/MM/YYYY')::text,
    to_char(a.created_at at time zone 'Europe/Lisbon', 'HH24:MI:SS')::text
  from public.activity_feed a
  left join public.profiles p on p.id = a.actor_id
  where a.club_id = target_club
    and (p_module is null or p_module = '' or p_module = 'all'
      or coalesce(a.metadata->>'module_code', a.activity_type) = p_module)
  order by a.created_at desc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
end;
$$;

revoke all on function public.activity_feed_portugal_v1(uuid,text,integer) from public, anon;
grant execute on function public.activity_feed_portugal_v1(uuid,text,integer) to authenticated;
'''
migration.parent.mkdir(parents=True, exist_ok=True)
migration.write_text(sql, encoding='utf-8')

s = repo.read_text(encoding='utf-8')
old = """    var query = _client
        .from('activity_feed')
        .select('id,activity_type,title,description,entity_type,entity_id,metadata,created_at,actor:profiles(full_name)')
        .eq('club_id', AppSession.instance.clubId);

    if (module != null && module.isNotEmpty && module != 'all') {
      query = query.eq('metadata->>module_code', module);
    }

    final response = await query
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(response);
"""
new = """    final response = await _client.rpc(
      'activity_feed_portugal_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_module': module,
        'p_limit': limit,
      },
    );
    return List<Map<String, dynamic>>.from(response as List);
"""
if old in s:
    s = s.replace(old, new, 1)
elif "activity_feed_portugal_v1" not in s:
    raise SystemExit('ERRO: não encontrei o bloco esperado em activity_repository.dart.')

needle = """  Future<List<Map<String, dynamic>>> notifications({int limit = 100}) async {
"""
history = """  Future<List<Map<String, dynamic>>> entityHistory({
    required String entityType,
    required String entityId,
    int limit = 100,
  }) async {
    if (AppConfig.demoMode) return const [];
    final response = await _client.rpc(
      'audit_entity_history_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_entity_type': entityType,
        'p_entity_id': entityId,
        'p_limit': limit,
      },
    );
    return List<Map<String, dynamic>>.from(response as List);
  }

"""
if 'Future<List<Map<String, dynamic>>> entityHistory' not in s:
    if needle not in s:
        raise SystemExit('ERRO: não encontrei ponto de inserção do histórico.')
    s = s.replace(needle, history + needle, 1)
repo.write_text(s, encoding='utf-8')

s = screen.read_text(encoding='utf-8')
old_actor = """    final actor = row['actor'];
    final actorName = actor is Map ? actor['full_name']?.toString() : null;
"""
new_actor = """    final actorName = row['actor_name']?.toString();
    final portugalDate = row['portugal_date']?.toString();
    final portugalTime = row['portugal_time']?.toString();
    final entityType = row['entity_type']?.toString();
    final entityId = row['entity_id']?.toString();
"""
if old_actor in s:
    s = s.replace(old_actor, new_actor, 1)
elif "final portugalDate = row['portugal_date']" not in s:
    raise SystemExit('ERRO: não encontrei o bloco do autor em activity_screen.dart.')

old_tile = """        subtitle: Text([
          row['description']?.toString(),
          if (actorName != null && actorName.isNotEmpty) 'Por $actorName',
          _relativeTime(row['created_at']),
        ].where((value) => value != null && value.isNotEmpty).join('\\n')),
        isThreeLine: true,
"""
new_tile = """        subtitle: Text([
          row['description']?.toString(),
          if (actorName != null && actorName.isNotEmpty) 'Registado por: $actorName',
          if (portugalDate != null && portugalTime != null)
            '$portugalDate às $portugalTime',
        ].where((value) => value != null && value.isNotEmpty).join('\\n')),
        isThreeLine: true,
        trailing: entityType != null && entityId != null
            ? const Icon(Icons.history_outlined)
            : null,
        onTap: entityType != null && entityId != null
            ? () => _showAuditHistory(context, entityType, entityId)
            : null,
"""
if old_tile in s:
    s = s.replace(old_tile, new_tile, 1)
elif "_showAuditHistory(context, entityType, entityId)" not in s:
    raise SystemExit('ERRO: não encontrei o ListTile esperado no Activity Feed.')

insert_before = """Color _priorityColor(BuildContext context, String priority) {
"""
helper = r'''Future<void> _showAuditHistory(
  BuildContext context,
  String entityType,
  String entityId,
) async {
  final repository = ActivityRepository();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.82,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: repository.entityHistory(entityType: entityType, entityId: entityId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Não foi possível carregar o histórico: ${snapshot.error}'),
            ));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Text('Histórico do registo', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('$entityType · $entityId', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              if (rows.isEmpty)
                const ListTile(leading: Icon(Icons.history_toggle_off_outlined), title: Text('Ainda não existem alterações auditadas para este registo.')),
              for (final item in rows)
                Card(
                  child: ListTile(
                    leading: Icon(_auditActionIcon(item['action']?.toString() ?? '')),
                    title: Text(_auditActionLabel(item['action']?.toString() ?? '')),
                    subtitle: Text([
                      'Utilizador: ${item['actor_name'] ?? 'Sistema'}',
                      if (item['portugal_date'] != null && item['portugal_time'] != null)
                        '${item['portugal_date']} às ${item['portugal_time']}',
                    ].join('\n')),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

String _auditActionLabel(String action) => switch (action.toLowerCase()) {
  'insert' || 'create' || 'created' => 'Registo criado',
  'update' || 'updated' => 'Registo alterado',
  'delete' || 'deleted' => 'Registo eliminado',
  _ => action.isEmpty ? 'Alteração' : action,
};

IconData _auditActionIcon(String action) => switch (action.toLowerCase()) {
  'insert' || 'create' || 'created' => Icons.add_circle_outline,
  'delete' || 'deleted' => Icons.delete_outline,
  _ => Icons.edit_outlined,
};

'''
if '_showAuditHistory(' not in s:
    if insert_before not in s:
        raise SystemExit('ERRO: não encontrei ponto para inserir o painel de histórico.')
    s = s.replace(insert_before, helper + insert_before, 1)
# The call itself contains _showAuditHistory, so distinguish definition.
if 'Future<void> _showAuditHistory(' not in s:
    if insert_before not in s:
        raise SystemExit('ERRO: não encontrei ponto para inserir o painel de histórico.')
    s = s.replace(insert_before, helper + insert_before, 1)
screen.write_text(s, encoding='utf-8')

print('Commit 5 parte 2 — interface de auditoria preparada com sucesso.')
print('Ficheiros alterados:')
print(' - apps/mobile/lib/repositories/activity_repository.dart')
print(' - apps/mobile/lib/screens/activity_screen.dart')
print(' - supabase/migrations/20260811161353_rc1_audit_ui_portugal.sql')
