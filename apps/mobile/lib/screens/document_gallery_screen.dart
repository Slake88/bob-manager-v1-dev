import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../repositories/documents_advanced_repository.dart';
import 'documents_ui_helpers.dart';

class DocumentGalleryScreen extends StatefulWidget {
  const DocumentGalleryScreen({
    super.key,
    required this.repository,
  });

  final DocumentsAdvancedRepository repository;

  @override
  State<DocumentGalleryScreen> createState() => _DocumentGalleryScreenState();
}

class _DocumentGalleryScreenState extends State<DocumentGalleryScreen> {
  late Future<List<Map<String, dynamic>>> _eventsFuture;
  String? _eventId;
  Future<List<Map<String, dynamic>>>? _galleryFuture;

  @override
  void initState() {
    super.initState();
    _eventsFuture = widget.repository.listEvents();
  }

  void _select(String? id) {
    setState(() {
      _eventId = id;
      _galleryFuture = id == null ? null : widget.repository.listGallery(id);
    });
  }

  Future<void> _upload() async {
    final eventId = _eventId;
    if (eventId == null) return;
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (result == null || result.files.isEmpty) return;
    try {
      await widget.repository.uploadGallery(eventId, result.files.single);
      if (!mounted) return;
      setState(() => _galleryFuture = widget.repository.listGallery(eventId));
      documentSnack(context, 'Fotografia adicionada à galeria.');
    } catch (error) {
      if (!mounted) return;
      documentSnack(context, documentFriendlyError(error));
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    try {
      final url = await widget.repository.signedUrl(row, action: 'download');
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
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _eventsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return DocumentErrorView(
            error: snapshot.error!,
            onRetry: () => setState(
              () => _eventsFuture = widget.repository.listEvents(),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final events = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField<String>(
                  initialValue: _eventId,
                  decoration: const InputDecoration(labelText: 'Evento'),
                  items: events
                      .map(
                        (row) => DropdownMenuItem<String>(
                          value: row['id'].toString(),
                          child: Text(row['name']?.toString() ?? 'Evento'),
                        ),
                      )
                      .toList(),
                  onChanged: _select,
                ),
              ),
            ),
            if (_eventId == null)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.photo_library_outlined),
                  title: Text('Seleciona um evento para abrir a galeria.'),
                ),
              )
            else ...[
              if (widget.repository.canManageGallery)
                FilledButton.icon(
                  onPressed: _upload,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Adicionar fotografia'),
                ),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _galleryFuture,
                builder: (context, gallerySnapshot) {
                  if (gallerySnapshot.hasError) {
                    return Text(
                      documentFriendlyError(gallerySnapshot.error!),
                    );
                  }
                  if (!gallerySnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rows = gallerySnapshot.data!;
                  if (rows.isEmpty) {
                    return const Card(
                      child: ListTile(title: Text('A galeria ainda está vazia.')),
                    );
                  }
                  return Column(
                    children: rows
                        .map(
                          (row) => Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.image_outlined),
                              ),
                              title: Text(
                                row['name']?.toString() ?? 'Fotografia',
                              ),
                              subtitle: Text(
                                DocumentsAdvancedRepository.formatBytes(
                                  num.tryParse(
                                        row['file_size']?.toString() ?? '',
                                      ) ??
                                      0,
                                ),
                              ),
                              trailing: const Icon(Icons.download_outlined),
                              onTap: () => _open(row),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }
}
