import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../repositories/documents_advanced_repository.dart';
import 'documents_ui_helpers.dart';

class DocumentAdvancedDetailScreen extends StatefulWidget {
  const DocumentAdvancedDetailScreen({
    super.key,
    required this.document,
    required this.repository,
  });

  final Map<String, dynamic> document;
  final DocumentsAdvancedRepository repository;

  @override
  State<DocumentAdvancedDetailScreen> createState() =>
      _DocumentAdvancedDetailScreenState();
}

class _DocumentAdvancedDetailScreenState
    extends State<DocumentAdvancedDetailScreen> {
  late Map<String, dynamic> _document;
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _document = Map<String, dynamic>.from(widget.document);
    _reload();
  }

  String get _id => _document['id'].toString();

  void _reload() {
    _future = Future.wait<dynamic>([
      widget.repository.listVersions(_id),
      widget.repository.listLinks(_id),
      widget.repository.listOcrJobs(_id),
    ]);
  }

  Future<void> _refreshDocument() async {
    _document = await widget.repository.document(_id);
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _openFile() async {
    try {
      final url = await widget.repository.signedUrl(
        _document,
        action: 'download',
      );
      if (!mounted) return;
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        documentSnack(context, 'Não foi possível abrir o ficheiro.');
      }
    } catch (error) {
      if (!mounted) return;
      documentSnack(context, documentFriendlyError(error));
    }
  }

  Future<void> _newVersion() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty || !mounted) return;
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nova versão'),
        content: TextField(
          controller: notes,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Alterações desta versão',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Carregar'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      notes.dispose();
      return;
    }
    try {
      await widget.repository.uploadVersion(
        document: _document,
        file: result.files.single,
        notes: notes.text,
      );
      notes.dispose();
      await _refreshDocument();
      if (!mounted) return;
      documentSnack(context, 'Nova versão registada.');
    } catch (error) {
      notes.dispose();
      if (!mounted) return;
      documentSnack(context, documentFriendlyError(error));
    }
  }

  Future<void> _addLink() async {
    final type = TextEditingController(text: 'event');
    final entityId = TextEditingController();
    final label = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ligar documento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: type,
              decoration: const InputDecoration(
                labelText: 'Tipo de entidade',
                hintText: 'event, member, asset...',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: entityId,
              decoration: const InputDecoration(
                labelText: 'ID da entidade (UUID)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: label,
              decoration: const InputDecoration(labelText: 'Descrição'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (type.text.trim().isEmpty || entityId.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Ligar'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      type.dispose();
      entityId.dispose();
      label.dispose();
      return;
    }
    try {
      await widget.repository.addLink(
        documentId: _id,
        entityType: type.text,
        entityId: entityId.text,
        label: label.text,
      );
      type.dispose();
      entityId.dispose();
      label.dispose();
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      type.dispose();
      entityId.dispose();
      label.dispose();
      if (!mounted) return;
      documentSnack(context, documentFriendlyError(error));
    }
  }

  Future<void> _requestApproval() async {
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pedir aprovação'),
        content: TextField(
          controller: notes,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Nota para a direção'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Submeter'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      notes.dispose();
      return;
    }
    try {
      await widget.repository.requestApproval(_id, notes: notes.text);
      notes.dispose();
      await _refreshDocument();
      if (!mounted) return;
      documentSnack(context, 'Documento enviado para aprovação.');
    } catch (error) {
      notes.dispose();
      if (!mounted) return;
      documentSnack(context, documentFriendlyError(error));
    }
  }

  Future<void> _runOcr() async {
    try {
      final result = await widget.repository.runOcr(_id);
      await _refreshDocument();
      if (!mounted) return;
      documentSnack(
        context,
        result['status'] == 'ready'
            ? 'OCR concluído.'
            : DocumentsAdvancedRepository.ocrLabel(result['status']),
      );
    } catch (error) {
      if (!mounted) return;
      documentSnack(context, documentFriendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_document['name']?.toString() ?? 'Documento')),
      body: FutureBuilder<List<dynamic>>(
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
          final versions =
              List<Map<String, dynamic>>.from(snapshot.data![0] as List);
          final links =
              List<Map<String, dynamic>>.from(snapshot.data![1] as List);
          final ocr =
              List<Map<String, dynamic>>.from(snapshot.data![2] as List);
          final latestOcr = ocr.isEmpty ? null : ocr.first;
          final canVersion = widget.repository.canManageDocuments &&
              _document['scope']?.toString() != 'personal';
          final canOcr = widget.repository.canRunOcr &&
              DocumentsAdvancedRepository.isOcrMime(
                _document['mime_type']?.toString(),
              );

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            label: Text(
                              DocumentsAdvancedRepository.scopeLabel(
                                _document['scope'],
                              ),
                            ),
                          ),
                          Chip(label: Text('v${_document['version'] ?? '1.0'}')),
                          Chip(
                            label: Text(
                              DocumentsAdvancedRepository.approvalLabel(
                                _document['approval_status'],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(_document['category']?.toString() ?? 'Documento'),
                      if (_document['description']
                              ?.toString()
                              .trim()
                              .isNotEmpty ==
                          true) ...[
                        const SizedBox(height: 6),
                        Text(_document['description'].toString()),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        DocumentsAdvancedRepository.formatBytes(
                          num.tryParse(
                                _document['file_size']?.toString() ?? '',
                              ) ??
                              0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_document['storage_path']?.toString().isNotEmpty == true)
                FilledButton.icon(
                  onPressed: _openFile,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Abrir ficheiro atual'),
                ),
              const SizedBox(height: 8),
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Versões'),
                  subtitle: Text('${versions.length} versão(ões)'),
                  children: [
                    if (versions.isEmpty)
                      const ListTile(title: Text('Sem histórico de versões.'))
                    else
                      ...versions.map(
                        (row) => ListTile(
                          leading: Icon(
                            row['is_current'] == true
                                ? Icons.check_circle
                                : Icons.history,
                          ),
                          title: Text('Versão ${row['version_label'] ?? '-'}'),
                          subtitle: Text(
                            '${row['original_file_name'] ?? 'Ficheiro'} • ${DocumentsAdvancedRepository.formatBytes(num.tryParse(row['file_size']?.toString() ?? '') ?? 0)}',
                          ),
                        ),
                      ),
                    if (canVersion)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonalIcon(
                            onPressed: _newVersion,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Nova versão'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Ligações'),
                  subtitle: Text('${links.length} ligação(ões)'),
                  children: [
                    if (links.isEmpty)
                      const ListTile(title: Text('Sem ligações registadas.'))
                    else
                      ...links.map(
                        (row) => ListTile(
                          title: Text(
                            row['label']?.toString() ??
                                row['linked_entity_type']?.toString() ??
                                'Ligação',
                          ),
                          subtitle: Text(
                            '${row['linked_entity_type'] ?? ''} • ${row['linked_entity_id'] ?? ''}',
                          ),
                        ),
                      ),
                    if (widget.repository.canManageDocuments)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonalIcon(
                            onPressed: _addLink,
                            icon: const Icon(Icons.add_link),
                            label: const Text('Adicionar ligação'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.approval_outlined),
                  title: const Text('Aprovação'),
                  subtitle: Text(
                    DocumentsAdvancedRepository.approvalLabel(
                      _document['approval_status'],
                    ),
                  ),
                  trailing: widget.repository.canManageDocuments
                      ? const Icon(Icons.chevron_right)
                      : null,
                  onTap: widget.repository.canManageDocuments
                      ? _requestApproval
                      : null,
                ),
              ),
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.document_scanner_outlined),
                  title: const Text('OCR'),
                  subtitle: Text(
                    DocumentsAdvancedRepository.ocrLabel(
                      latestOcr?['status'] ?? _document['ocr_status'],
                    ),
                  ),
                  children: [
                    if (latestOcr?['raw_text']
                            ?.toString()
                            .trim()
                            .isNotEmpty ==
                        true)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: SelectableText(latestOcr!['raw_text'].toString()),
                      ),
                    if (latestOcr?['error_message']
                            ?.toString()
                            .trim()
                            .isNotEmpty ==
                        true)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(latestOcr!['error_message'].toString()),
                      ),
                    if (canOcr)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonalIcon(
                            onPressed: _runOcr,
                            icon: const Icon(Icons.document_scanner),
                            label: const Text('Executar OCR'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
