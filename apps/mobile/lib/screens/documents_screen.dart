import 'package:flutter/material.dart';

import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/entity_definition.dart';
import '../core/permissions.dart';
import '../repositories/document_repository.dart';
import 'entity_form_screen.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final DocumentRepository _repository = DocumentRepository();
  late Future<List<Map<String, dynamic>>> _future;

  AppRole get _role => AppRole.fromValue(AppSession.instance.role);
  bool get _canManage =>
      PermissionPolicy.allows(_role, AppPermission.manageDocuments);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _repository.listDocuments();

  Future<void> _openForm([Map<String, dynamic>? row]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EntityFormScreen(
          definition: documentsDefinition,
          initialValues: row,
          onSave: (values, id) async {
            await _repository.saveDocument(values, documentId: id);
          },
        ),
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  String _status(Map<String, dynamic> row) {
    if (DocumentRepository.isExpired(row)) return 'Expirado';
    if (DocumentRepository.expiresSoon(row)) return 'Expira em breve';
    return row['status']?.toString() ?? 'Ativo';
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
                Text('Documentos e Arquivo',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  const Card(
                    child: ListTile(title: Text('Sem documentos registados.')),
                  )
                else
                  ...rows.map((row) {
                    final sensitive = row['sensitive'] == true;
                    return Card(
                      child: ListTile(
                        leading: Icon(sensitive
                            ? Icons.lock_outline
                            : Icons.description_outlined),
                        title: Text(row['name']?.toString() ?? 'Documento'),
                        subtitle: Text([
                          row['category'],
                          _status(row),
                          row['expires_at'] == null
                              ? null
                              : 'Validade: ${row['expires_at']}',
                        ]
                            .where((value) => value != null)
                            .join(' • ')),
                        trailing: _canManage
                            ? IconButton(
                                onPressed: () => _openForm(row),
                                icon: const Icon(Icons.edit_outlined),
                              )
                            : null,
                        onTap: _canManage ? () => _openForm(row) : null,
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
              label: const Text('Novo documento'),
            )
          : null,
    );
  }
}
