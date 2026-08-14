import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../repositories/documents_advanced_repository.dart';
import 'documents_ui_helpers.dart';

class DocumentPersonalArchiveScreen extends StatefulWidget {
  const DocumentPersonalArchiveScreen({
    super.key,
    required this.repository,
  });

  final DocumentsAdvancedRepository repository;

  @override
  State<DocumentPersonalArchiveScreen> createState() =>
      _DocumentPersonalArchiveScreenState();
}

class _DocumentPersonalArchiveScreenState
    extends State<DocumentPersonalArchiveScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = Future.wait<dynamic>([
      widget.repository.listPersonal(),
      widget.repository.personalUsageBytes(),
    ]);
  }

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    try {
      await widget.repository.uploadPersonal(result.files.single);
      if (!mounted) return;
      setState(_reload);
      documentSnack(context, 'Documento guardado no teu arquivo privado.');
    } catch (error) {
      if (!mounted) return;
      documentSnack(context, documentFriendlyError(error));
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    try {
      final url = await widget.repository.signedUrl(
        row,
        action: 'download',
      );
      if (!mounted) return;
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      if (!mounted) return;
      documentSnack(context, documentFriendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
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
        final rows =
            List<Map<String, dynamic>>.from(snapshot.data![0] as List);
        final used = snapshot.data![1] as int;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Meu arquivo privado',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Os documentos pessoais só são visíveis por ti e pela direção autorizada.',
                    ),
                    const SizedBox(height: 14),
                    LinearProgressIndicator(
                      value: DocumentsAdvancedRepository.usageRatio(used),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${DocumentsAdvancedRepository.formatBytes(used)} de 500 MB utilizados',
                    ),
                  ],
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: _upload,
              icon: const Icon(Icons.upload_file),
              label: const Text('Guardar documento pessoal'),
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              const Card(
                child: ListTile(title: Text('O teu arquivo está vazio.')),
              )
            else
              ...rows.map(
                (row) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(documentIcon(row['mime_type'])),
                    ),
                    title: Text(
                      row['name']?.toString() ?? 'Documento pessoal',
                    ),
                    subtitle: Text(
                      '${DocumentsAdvancedRepository.formatBytes(num.tryParse(row['file_size']?.toString() ?? '') ?? 0)} • privado',
                    ),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _open(row),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
