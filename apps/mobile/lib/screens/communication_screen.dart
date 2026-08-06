import 'package:flutter/material.dart';

import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/entity_definition.dart';
import '../core/permissions.dart';
import '../repositories/communication_repository.dart';
import 'entity_form_screen.dart';

class CommunicationScreen extends StatefulWidget {
  const CommunicationScreen({super.key});

  @override
  State<CommunicationScreen> createState() => _CommunicationScreenState();
}

class _CommunicationScreenState extends State<CommunicationScreen> {
  final CommunicationRepository _repository = CommunicationRepository();
  late Future<List<Map<String, dynamic>>> _future;

  AppRole get _role => AppRole.fromValue(AppSession.instance.role);
  bool get _canManage =>
      PermissionPolicy.allows(_role, AppPermission.manageCommunication);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _repository.listAnnouncements();

  Future<void> _openForm([Map<String, dynamic>? row]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EntityFormScreen(
          definition: communicationDefinition,
          initialValues: row,
          onSave: (values, id) async {
            await _repository.saveAnnouncement(values, announcementId: id);
          },
        ),
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _acknowledge(Map<String, dynamic> row) async {
    await _repository.acknowledge(row['id'].toString());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Leitura confirmada.')),
    );
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text('Centro de Comunicação',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  const Card(
                    child: ListTile(title: Text('Sem comunicados publicados.')),
                  )
                else
                  ...rows.map((row) {
                    final requiresAck = row['requires_acknowledgement'] == true;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.campaign_outlined),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    row['title']?.toString() ?? 'Comunicado',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                if (_canManage)
                                  IconButton(
                                    onPressed: () => _openForm(row),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(row['body']?.toString() ?? ''),
                            const SizedBox(height: 10),
                            Text(
                              [
                                row['priority'],
                                row['audience'],
                                row['published_at'],
                              ].where((value) => value != null).join(' • '),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (requiresAck) ...[
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.tonalIcon(
                                  onPressed: () => _acknowledge(row),
                                  icon: const Icon(Icons.done_all),
                                  label: const Text('Confirmar leitura'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: const Text('Novo comunicado'),
            )
          : null,
    );
  }
}
