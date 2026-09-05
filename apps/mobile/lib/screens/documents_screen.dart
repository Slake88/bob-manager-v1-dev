import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

  Future<void> _edit(Map<String, dynamic> row) async {
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

  Future<void> _upload() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _DocumentUploadDialog(repository: _repository),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _open(Map<String, dynamic> row) async {
    try {
      final url = await _repository.signedUrl(row);
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw StateError('Não foi possível abrir o ficheiro.');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar documento'),
        content: Text(
          'Eliminar definitivamente “${row['name'] ?? 'Documento'}” e o ficheiro associado?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _repository.deleteDocument(row);
      if (mounted) setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
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
                Text(
                  'Documentos e Arquivo',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  const Card(
                    child: ListTile(title: Text('Sem documentos registados.')),
                  )
                else
                  ...rows.map((row) {
                    final sensitive = row['sensitive'] == true;
                    final hasFile =
                        (row['storage_path']?.toString().isNotEmpty ?? false);
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          sensitive
                              ? Icons.lock_outline
                              : Icons.description_outlined,
                        ),
                        title: Text(row['name']?.toString() ?? 'Documento'),
                        subtitle: Text([
                          row['category'],
                          _status(row),
                          row['expires_at'] == null
                              ? null
                              : 'Validade: ${row['expires_at']}',
                          row['original_file_name'],
                        ].where((value) => value != null).join(' • ')),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            if (hasFile)
                              IconButton(
                                tooltip: 'Abrir ficheiro',
                                onPressed: () => _open(row),
                                icon: const Icon(Icons.open_in_new),
                              ),
                            if (_canManage)
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') _edit(row);
                                  if (value == 'delete') _delete(row);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Editar metadados'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Eliminar'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        onTap: hasFile ? () => _open(row) : null,
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
              onPressed: _upload,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Carregar documento'),
            )
          : null,
    );
  }
}

class _DocumentUploadDialog extends StatefulWidget {
  const _DocumentUploadDialog({required this.repository});

  final DocumentRepository repository;

  @override
  State<_DocumentUploadDialog> createState() =>
      _DocumentUploadDialogState();
}

class _DocumentUploadDialogState extends State<_DocumentUploadDialog> {
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _description = TextEditingController();
  final _documentDate = TextEditingController();
  final _expiresAt = TextEditingController();
  final _version = TextEditingController(text: '1.0');
  PlatformFile? _file;
  bool _sensitive = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _description.dispose();
    _documentDate.dispose();
    _expiresAt.dispose();
    _version.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: false,
      allowedExtensions: const [
        'pdf',
        'jpg',
        'jpeg',
        'png',
        'webp',
        'doc',
        'docx',
        'xls',
        'xlsx',
      ],
      type: FileType.custom,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    setState(() {
      _file = file;
      if (_name.text.trim().isEmpty) {
        _name.text = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      }
    });
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null || file.bytes == null || _name.text.trim().isEmpty) {
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.repository.uploadDocument(
        values: {
          'name': _name.text.trim(),
          'category': _category.text.trim().isEmpty
              ? null
              : _category.text.trim(),
          'description': _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          'document_date': _documentDate.text.trim().isEmpty
              ? null
              : _documentDate.text.trim(),
          'expires_at': _expiresAt.text.trim().isEmpty
              ? null
              : _expiresAt.text.trim(),
          'version': _version.text.trim().isEmpty ? null : _version.text.trim(),
          'status': 'active',
          'sensitive': _sensitive,
        },
        fileName: file.name,
        bytes: file.bytes!,
        mimeType: _mimeType(file.extension),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _mimeType(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Carregar documento'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file),
                title: Text(_file?.name ?? 'Nenhum ficheiro selecionado'),
                subtitle: _file == null
                    ? const Text('PDF, imagem, Word ou Excel — máximo 20 MB')
                    : Text('${(_file!.size / 1024).toStringAsFixed(1)} KB'),
                trailing: OutlinedButton(
                  onPressed: _saving ? null : _pickFile,
                  child: const Text('Escolher'),
                ),
              ),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: _category,
                decoration: const InputDecoration(labelText: 'Categoria'),
              ),
              TextField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Descrição'),
                maxLines: 2,
              ),
              TextField(
                controller: _documentDate,
                decoration: const InputDecoration(
                  labelText: 'Data do documento',
                  hintText: 'AAAA-MM-DD',
                ),
              ),
              TextField(
                controller: _expiresAt,
                decoration: const InputDecoration(
                  labelText: 'Validade',
                  hintText: 'AAAA-MM-DD',
                ),
              ),
              TextField(
                controller: _version,
                decoration: const InputDecoration(labelText: 'Versão'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Documento sensível'),
                subtitle: const Text('Visível apenas para cargos autorizados'),
                value: _sensitive,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _sensitive = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Carregar'),
        ),
      ],
    );
  }
}
