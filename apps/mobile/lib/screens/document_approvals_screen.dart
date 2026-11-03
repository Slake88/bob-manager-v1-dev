import 'package:flutter/material.dart';

import '../repositories/documents_advanced_repository.dart';
import 'documents_ui_helpers.dart';

class DocumentApprovalsScreen extends StatefulWidget {
  const DocumentApprovalsScreen({
    super.key,
    required this.repository,
  });

  final DocumentsAdvancedRepository repository;

  @override
  State<DocumentApprovalsScreen> createState() =>
      _DocumentApprovalsScreenState();
}

class _DocumentApprovalsScreenState extends State<DocumentApprovalsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = widget.repository.listApprovals();

  Future<void> _decide(Map<String, dynamic> row, bool approve) async {
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Aprovar documento' : 'Rejeitar documento'),
        content: TextField(
          controller: notes,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Observação'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(approve ? 'Aprovar' : 'Rejeitar'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      notes.dispose();
      return;
    }
    try {
      await widget.repository.decideApproval(
        row['id'].toString(),
        approve: approve,
        notes: notes.text,
      );
      notes.dispose();
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      notes.dispose();
      if (!mounted) return;
      documentSnack(context, documentFriendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return DocumentErrorView(
            error: snapshot.error!,
            onRetry: () => setState(_reload),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.approval_outlined),
                ),
                title: const Text('Aprovações documentais'),
                subtitle: Text(
                  widget.repository.canApprove
                      ? 'Revê pedidos pendentes e mantém o histórico de decisões.'
                      : 'Consulta o estado dos pedidos a que tens acesso.',
                ),
              ),
            ),
            if (rows.isEmpty)
              const Card(
                child: ListTile(title: Text('Sem pedidos de aprovação.')),
              )
            else
              ...rows.map((row) {
                final document = row['documents'];
                final name = document is Map
                    ? document['name']?.toString() ?? 'Documento'
                    : 'Documento';
                final pending = row['status'] == 'pending';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Chip(
                              label: Text(
                                DocumentsAdvancedRepository.approvalLabel(
                                  row['status'],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (row['notes']?.toString().trim().isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(row['notes'].toString()),
                          ),
                        if (pending && widget.repository.canApprove) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: () => _decide(row, true),
                                icon: const Icon(Icons.check),
                                label: const Text('Aprovar'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _decide(row, false),
                                icon: const Icon(Icons.close),
                                label: const Text('Rejeitar'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
