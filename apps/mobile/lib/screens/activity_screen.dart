import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/activity_repository.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final ActivityRepository _repository = ActivityRepository();
  String _module = 'all';
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _repository.activity(module: _module);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text(
                'Activity Feed',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 4),
              const Text('O que aconteceu no clube, por ordem cronológica.'),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _filters.map((item) {
                    final selected = _module == item.$1;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: selected,
                        avatar: Icon(item.$3, size: 18),
                        label: Text(item.$2),
                        onSelected: (_) {
                          setState(() {
                            _module = item.$1;
                            _reload();
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.history_toggle_off_outlined),
                    title: Text('Ainda não existem atividades para mostrar.'),
                  ),
                )
              else
                ...rows.map((row) => _ActivityCard(row: row)),
            ],
          ),
        );
      },
    );
  }
}

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  final ActivityRepository _repository = ActivityRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _repository.notifications();
  }

  Future<void> _markAll() async {
    await _repository.markAllRead();
    if (mounted) setState(_reload);
  }

  Future<void> _toggle(Map<String, dynamic> row) async {
    await _repository.markRead(
      row['id'].toString(),
      read: row['read_at'] == null,
    );
    if (mounted) setState(_reload);
  }

  Future<void> _archive(Map<String, dynamic> row) async {
    await _repository.archive(row['id'].toString());
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        actions: [
          TextButton.icon(
            onPressed: _markAll,
            icon: const Icon(Icons.done_all),
            label: const Text('Marcar todas'),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Não tens notificações.'),
              ),
            );
          }

          final unreadCount = rows.where((row) => row['read_at'] == null).length;
          final urgentCount = rows.where((row) {
            return row['read_at'] == null &&
                row['priority']?.toString().toLowerCase() == 'high';
          }).length;

          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
              children: [
                if (unreadCount > 0)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Chip(
                            avatar: const Icon(Icons.notifications_active_outlined, size: 18),
                            label: Text('$unreadCount novas'),
                          ),
                          if (urgentCount > 0)
                            Chip(
                              avatar: const Icon(Icons.priority_high, size: 18),
                              label: Text('$urgentCount urgentes'),
                            ),
                          TextButton.icon(
                            onPressed: _markAll,
                            icon: const Icon(Icons.done_all),
                            label: const Text('Marcar todas como lidas'),
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final row in rows) _NotificationCard(
                  row: row,
                  onToggle: () => _toggle(row),
                  onArchive: () => _archive(row),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.row,
    required this.onToggle,
    required this.onArchive,
  });

  final Map<String, dynamic> row;
  final VoidCallback onToggle;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final unread = row['read_at'] == null;
    final module = row['module_code']?.toString() ?? 'general';
    final priority = row['priority']?.toString().toLowerCase() ?? 'normal';
    final colors = Theme.of(context).colorScheme;
    final accent = _priorityColor(context, priority);
    final background = unread
        ? Color.alphaBlend(colors.primary.withValues(alpha: 0.14), colors.surface)
        : colors.surfaceContainerLow;

    return Card(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: unread ? accent.withValues(alpha: 0.9) : colors.outlineVariant,
          width: unread ? 1.4 : 0.5,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: unread ? 5 : 2,
              decoration: BoxDecoration(
                color: unread ? accent : Colors.transparent,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
              ),
            ),
            Expanded(
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      backgroundColor: unread
                          ? accent.withValues(alpha: 0.16)
                          : colors.surfaceContainerHighest,
                      child: Icon(
                        _moduleIcon(module),
                        color: unread ? accent : colors.onSurfaceVariant,
                      ),
                    ),
                    if (unread)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: background, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                title: Text(
                  row['title']?.toString() ?? 'Notificação',
                  style: TextStyle(
                    fontWeight: unread ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
                subtitle: Text([
                  row['body']?.toString(),
                  _relativeTime(row['created_at']),
                ].where((value) => value != null && value.isNotEmpty).join('\n')),
                isThreeLine: true,
                onTap: onToggle,
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'toggle') onToggle();
                    if (value == 'archive') onArchive();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(
                        unread ? 'Marcar como lida' : 'Marcar como não lida',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'archive',
                      child: Text('Arquivar'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final metadata = row['metadata'];
    final module = metadata is Map
        ? metadata['module_code']?.toString() ??
            row['activity_type']?.toString() ??
            'general'
        : row['activity_type']?.toString() ?? 'general';
    final actorName = row['actor_name']?.toString();
    final portugalDate = row['portugal_date']?.toString();
    final portugalTime = row['portugal_time']?.toString();
    final entityType = row['entity_type']?.toString();
    final entityId = row['entity_id']?.toString();
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(_moduleIcon(module))),
        title: Text(row['title']?.toString() ?? 'Atividade'),
        subtitle: Text([
          row['description']?.toString(),
          if (actorName != null && actorName.isNotEmpty) 'Registado por: $actorName',
          if (portugalDate != null && portugalTime != null)
            '$portugalDate às $portugalTime',
        ].where((value) => value != null && value.isNotEmpty).join('\n')),
        isThreeLine: true,
        trailing: entityType != null && entityId != null
            ? const Icon(Icons.history_outlined)
            : null,
        onTap: entityType != null && entityId != null
            ? () => _showAuditHistory(context, entityType, entityId)
            : null,
      ),
    );
  }
}

Future<void> _showAuditHistory(
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

Color _priorityColor(BuildContext context, String priority) {
  final colors = Theme.of(context).colorScheme;
  return switch (priority) {
    'high' || 'urgent' => colors.error,
    'medium' => Colors.orange,
    _ => colors.primary,
  };
}

String _relativeTime(Object? raw) {
  final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inMinutes < 1) return 'Agora';
  if (diff.inMinutes < 60) return 'Há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'Há ${diff.inHours} h';
  if (diff.inDays == 1) return 'Ontem, ${DateFormat('HH:mm').format(date)}';
  if (diff.inDays < 7) return 'Há ${diff.inDays} dias';
  return DateFormat('dd/MM/yyyy HH:mm').format(date);
}

IconData _moduleIcon(String module) => switch (module) {
      'members' || 'member' => Icons.groups_outlined,
      'treasury' || 'transaction' => Icons.account_balance_wallet_outlined,
      'fees' || 'fee' => Icons.receipt_long_outlined,
      'lottery' || 'euromillions' => Icons.casino_outlined,
      'events' || 'event' => Icons.event_outlined,
      'inventory' || 'product' => Icons.inventory_2_outlined,
      'documents' || 'document' => Icons.folder_outlined,
      'communication' || 'announcement' => Icons.campaign_outlined,
      'emergency' => Icons.emergency_outlined,
      'settings' || 'permission' => Icons.admin_panel_settings_outlined,
      _ => Icons.notifications_none_outlined,
    };

const _filters = <(String, String, IconData)>[
  ('all', 'Tudo', Icons.all_inbox_outlined),
  ('members', 'Membros', Icons.groups_outlined),
  ('treasury', 'Tesouraria', Icons.account_balance_wallet_outlined),
  ('fees', 'Quotas', Icons.receipt_long_outlined),
  ('lottery', 'Euromilhões', Icons.casino_outlined),
  ('events', 'Eventos', Icons.event_outlined),
  ('inventory', 'Inventário', Icons.inventory_2_outlined),
  ('documents', 'Documentos', Icons.folder_outlined),
  ('communication', 'Comunicação', Icons.campaign_outlined),
];
