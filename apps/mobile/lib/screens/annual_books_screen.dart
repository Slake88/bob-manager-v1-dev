import 'package:flutter/material.dart';

import '../repositories/documents_advanced_repository.dart';
import 'documents_ui_helpers.dart';

class AnnualBooksScreen extends StatefulWidget {
  const AnnualBooksScreen({
    super.key,
    required this.repository,
  });

  final DocumentsAdvancedRepository repository;

  @override
  State<AnnualBooksScreen> createState() => _AnnualBooksScreenState();
}

class _AnnualBooksScreenState extends State<AnnualBooksScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = widget.repository.listAnnualBooks();

  Future<void> _create() async {
    final title = TextEditingController(
      text: 'Livro anual ${DateTime.now().year}',
    );
    final year = TextEditingController(text: '${DateTime.now().year}');
    final description = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nova Cápsula do Tempo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: year,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Ano'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final parsedYear = int.tryParse(year.text);
              if (parsedYear == null || title.text.trim().isEmpty) return;
              try {
                await widget.repository.saveAnnualBook(
                  year: parsedYear,
                  title: title.text,
                  description: description.text,
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  documentSnack(
                    dialogContext,
                    documentFriendlyError(error),
                  );
                }
              }
            },
            child: const Text('Criar'),
          ),
        ],
      ),
    );
    title.dispose();
    year.dispose();
    description.dispose();
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _open(Map<String, dynamic> row) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AnnualBookEditorScreen(
          book: row,
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
        return Scaffold(
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              const Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(Icons.auto_stories)),
                  title: Text('Cápsula do Tempo'),
                  subtitle: Text(
                    'Constrói um livro anual com memórias, documentos e marcos do clube.',
                  ),
                ),
              ),
              if (rows.isEmpty)
                const Card(
                  child: ListTile(
                    title: Text('Ainda não existem livros anuais.'),
                  ),
                )
              else
                ...rows.map(
                  (row) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${row['year'] ?? ''}')),
                      title: Text(row['title']?.toString() ?? 'Livro anual'),
                      subtitle: Text(row['status']?.toString() ?? 'draft'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(row),
                    ),
                  ),
                ),
            ],
          ),
          floatingActionButton: widget.repository.canManageBooks
              ? FloatingActionButton.extended(
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                  label: const Text('Novo livro'),
                )
              : null,
        );
      },
    );
  }
}

class AnnualBookEditorScreen extends StatefulWidget {
  const AnnualBookEditorScreen({
    super.key,
    required this.book,
    required this.repository,
  });

  final Map<String, dynamic> book;
  final DocumentsAdvancedRepository repository;

  @override
  State<AnnualBookEditorScreen> createState() => _AnnualBookEditorScreenState();
}

class _AnnualBookEditorScreenState extends State<AnnualBookEditorScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  late Map<String, dynamic> _book;

  @override
  void initState() {
    super.initState();
    _book = Map<String, dynamic>.from(widget.book);
    _reload();
  }

  String get _bookId => _book['id'].toString();
  int get _year =>
      int.tryParse(_book['year']?.toString() ?? '') ?? DateTime.now().year;

  void _reload() => _future = widget.repository.listBookItems(_bookId);

  Future<void> _addCustom(int sequence) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Novo capítulo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: body,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Texto / memória'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty) return;
              try {
                await widget.repository.addBookItem(
                  bookId: _bookId,
                  sequence: sequence,
                  title: title.text,
                  body: body.text,
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  documentSnack(
                    dialogContext,
                    documentFriendlyError(error),
                  );
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    title.dispose();
    body.dispose();
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _addDocument(int sequence) async {
    final documents = await widget.repository.listDocuments();
    if (!mounted) return;
    final candidates = documents
        .where((row) => row['scope']?.toString() != 'personal')
        .toList();
    if (candidates.isEmpty) {
      documentSnack(context, 'Não existem documentos disponíveis.');
      return;
    }
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Adicionar documento'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: ListView.builder(
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final row = candidates[index];
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(row['name']?.toString() ?? 'Documento'),
                subtitle: Text(row['category']?.toString() ?? 'Documento'),
                onTap: () => Navigator.pop(dialogContext, row),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    try {
      await widget.repository.addBookItem(
        bookId: _bookId,
        sequence: sequence,
        title: selected['name']?.toString() ?? 'Documento',
        body: selected['description']?.toString() ??
            selected['category']?.toString() ??
            '',
        itemType: 'document',
        documentId: selected['id'].toString(),
        entityType: 'document',
        entityId: selected['id'].toString(),
        eventDate: DateTime.tryParse(
          selected['document_date']?.toString() ?? '',
        ),
      );
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      documentSnack(context, documentFriendlyError(error));
    }
  }

  Future<void> _addTimeline(int sequence) async {
    final timeline = await widget.repository.timelineForYear(_year);
    if (!mounted) return;
    if (timeline.isEmpty) {
      documentSnack(context, 'A timeline de $_year não tem registos.');
      return;
    }
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Timeline de $_year'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: ListView.builder(
            itemCount: timeline.length,
            itemBuilder: (context, index) {
              final row = timeline[index];
              return ListTile(
                leading: const Icon(Icons.timeline_outlined),
                title: Text(row['title']?.toString() ?? 'Marco'),
                subtitle: Text(
                  '${row['event_date'] ?? ''}${row['description']?.toString().trim().isNotEmpty == true ? ' • ${row['description']}' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(dialogContext, row),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    try {
      await widget.repository.addBookItem(
        bookId: _bookId,
        sequence: sequence,
        title: selected['title']?.toString() ?? 'Marco da timeline',
        body: selected['description']?.toString() ?? '',
        itemType: 'timeline',
        entityType: 'member_timeline',
        entityId: selected['id'].toString(),
        eventDate: DateTime.tryParse(
          selected['event_date']?.toString() ?? '',
        ),
      );
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      documentSnack(context, documentFriendlyError(error));
    }
  }

  Future<void> _preview() async {
    final items = await widget.repository.listBookItems(_bookId);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AnnualBookPreviewScreen(
          book: _book,
          items: items,
        ),
      ),
    );
  }

  Future<void> _publish() async {
    try {
      final updated = await widget.repository.saveAnnualBook(
        id: _bookId,
        year: _year,
        title: _book['title']?.toString() ?? 'Livro anual $_year',
        description: _book['description']?.toString() ?? '',
        status: 'published',
      );
      if (!mounted) return;
      setState(() => _book = updated);
      documentSnack(context, 'Livro anual publicado.');
    } catch (error) {
      if (!mounted) return;
      documentSnack(context, documentFriendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_book['title']?.toString() ?? 'Livro anual'),
        actions: [
          IconButton(
            tooltip: 'Pré-visualização',
            onPressed: _preview,
            icon: const Icon(Icons.preview_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
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
          final next = rows.length + 1;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: Text('Ano $_year'),
                  subtitle: Text(
                    _book['description']?.toString() ?? 'Cápsula do Tempo',
                  ),
                  trailing: Chip(
                    label: Text(_book['status']?.toString() ?? 'draft'),
                  ),
                ),
              ),
              if (rows.isEmpty)
                const Card(
                  child: ListTile(title: Text('Adiciona o primeiro capítulo.')),
                )
              else
                ...rows.map(
                  (row) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${row['sequence_no']}')),
                      title: Text(row['title']?.toString() ?? 'Capítulo'),
                      subtitle: Text(
                        '${_itemTypeLabel(row['item_type'])}${row['body']?.toString().trim().isNotEmpty == true ? ' • ${row['body']}' : ''}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: widget.repository.canManageBooks
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                try {
                                  await widget.repository.deleteBookItem(
                                    row['id'].toString(),
                                  );
                                  if (!mounted) return;
                                  setState(_reload);
                                } catch (error) {
                                  if (!mounted) return;
                                  documentSnack(
                                    context,
                                    documentFriendlyError(error),
                                  );
                                }
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              if (widget.repository.canManageBooks) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _addCustom(next),
                      icon: const Icon(Icons.add),
                      label: const Text('Capítulo'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _addDocument(next),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Documento'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _addTimeline(next),
                      icon: const Icon(Icons.timeline_outlined),
                      label: const Text('Timeline'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _publish,
                  icon: const Icon(Icons.publish_outlined),
                  label: const Text('Publicar livro anual'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class AnnualBookPreviewScreen extends StatelessWidget {
  const AnnualBookPreviewScreen({
    super.key,
    required this.book,
    required this.items,
  });

  final Map<String, dynamic> book;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pré-visualização')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            book['title']?.toString() ?? 'Livro anual',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '${book['year'] ?? ''}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (book['description']?.toString().trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(book['description'].toString()),
          ],
          const Divider(height: 32),
          if (items.isEmpty)
            const Text('Este livro ainda não tem conteúdo.')
          else
            ...items.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row['title']?.toString() ?? 'Capítulo',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _itemTypeLabel(row['item_type']),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    if (row['body']?.toString().trim().isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text(row['body'].toString()),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _itemTypeLabel(Object? value) => switch (value?.toString()) {
      'document' => 'Documento',
      'event' => 'Evento',
      'member' => 'Membro',
      'timeline' => 'Timeline',
      _ => 'Capítulo',
    };
