import 'package:flutter/material.dart';

import '../repositories/documents_advanced_repository.dart';
import 'document_advanced_detail_screen.dart';
import 'documents_screen.dart';
import 'documents_ui_helpers.dart';

class DocumentLibraryAdvancedScreen extends StatefulWidget {
  const DocumentLibraryAdvancedScreen({
    super.key,
    required this.repository,
  });

  final DocumentsAdvancedRepository repository;

  @override
  State<DocumentLibraryAdvancedScreen> createState() =>
      _DocumentLibraryAdvancedScreenState();
}

class _DocumentLibraryAdvancedScreenState
    extends State<DocumentLibraryAdvancedScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = widget.repository.listDocuments();

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _openManager() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Gestão da biblioteca')),
          body: const DocumentsScreen(),
        ),
      ),
    );
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _open(Map<String, dynamic> row) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DocumentAdvancedDetailScreen(
          document: row,
          repository: widget.repository,
        ),
      ),
    );
    if (!mounted) return;
    setState(_reload);
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
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.tune_outlined)),
                  title: const Text('Gestão da biblioteca'),
                  subtitle: const Text(
                    'Adicionar, editar ou remover os documentos gerais do clube.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openManager,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Arquivo documental',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                const Card(
                  child: ListTile(title: Text('Ainda não existem documentos.')),
                )
              else
                ...rows.map(
                  (row) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(documentIcon(row['mime_type'])),
                      ),
                      title: Text(row['name']?.toString() ?? 'Documento'),
                      subtitle: Text(
                        '${DocumentsAdvancedRepository.scopeLabel(row['scope'])} • v${row['version'] ?? '1.0'}\n${row['category'] ?? 'Documento'}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(row),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
