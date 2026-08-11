import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../repositories/financial_documents_repository.dart';

class FinancialDocumentGallery extends StatefulWidget {
  const FinancialDocumentGallery({
    super.key,
    required this.repository,
    required this.transactionId,
    required this.canManage,
    this.onChanged,
  });

  final FinancialDocumentsRepository repository;
  final String transactionId;
  final bool canManage;
  final Future<void> Function()? onChanged;

  @override
  State<FinancialDocumentGallery> createState() =>
      _FinancialDocumentGalleryState();
}

class _FinancialDocumentGalleryState extends State<FinancialDocumentGallery> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.repository.listForTransaction(widget.transactionId);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _notifyChanged() async {
    final callback = widget.onChanged;
    if (callback != null) await callback();
    await _refresh();
  }

  Future<void> _addDocuments() async {
    if (_busy) return;
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              title: Text(
                'Categoria do documento',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Talão / recibo'),
              onTap: () => Navigator.pop(context, 'receipt'),
            ),
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Comprovativo de pagamento'),
              onTap: () => Navigator.pop(context, 'payment_proof'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Fatura / PDF / outro'),
              onTap: () => Navigator.pop(context, 'invoice_other'),
            ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.repository.uploadFiles(
        transactionId: widget.transactionId,
        documentType: type,
        files: result.files,
      );
      await _notifyChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.files.length == 1
                ? 'Documento adicionado.'
                : '${result.files.length} documentos adicionados.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível carregar: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> document) async {
    try {
      final url = await widget.repository.signedUrl(document);
      if (!mounted) return;

      if (FinancialDocumentsRepository.isImage(document)) {
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: Stack(
              children: [
                ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 1100, maxHeight: 820),
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5,
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
        );
        return;
      }

      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw StateError('Não foi possível abrir o documento.');
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  Future<void> _setPrimary(Map<String, dynamic> document) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.setPrimary(
        transactionId: widget.transactionId,
        documentId: document['id'].toString(),
      );
      await _notifyChanged();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> document) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar documento?'),
        content: Text(
          'Eliminar “${document['original_file_name'] ?? 'Documento'}” deste movimento?',
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
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.repository.deleteDocument(
        transactionId: widget.transactionId,
        document: document,
      );
      await _notifyChanged();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Erro ao carregar documentos'),
              subtitle: Text('${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Card(
            child: SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final documents = snapshot.data!;
        Map<String, dynamic>? primary;
        for (final document in documents) {
          if (document['is_primary'] == true) {
            primary = document;
            break;
          }
        }
        primary ??= documents.isEmpty ? null : documents.first;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Documentos & comprovativos',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                if (widget.canManage)
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _addDocuments,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Adicionar'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (primary == null)
              Card(
                child: InkWell(
                  onTap: widget.canManage ? _addDocuments : null,
                  child: const SizedBox(
                    height: 170,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_open_outlined, size: 44),
                          SizedBox(height: 8),
                          Text('Sem documentos associados.'),
                          SizedBox(height: 4),
                          Text('PDF ou imagens · máximo 20 MB por ficheiro'),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else ...[
              _PrimaryDocumentCard(
                repository: widget.repository,
                document: primary,
                onOpen: () => _open(primary!),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 118,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: documents.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final document = documents[index];
                    return _DocumentThumbnail(
                      repository: widget.repository,
                      document: document,
                      canManage: widget.canManage,
                      onOpen: () => _open(document),
                      onPrimary: document['is_primary'] == true
                          ? null
                          : () => _setPrimary(document),
                      onDelete: widget.canManage &&
                              FinancialDocumentsRepository.isDeletable(document)
                          ? () => _delete(document)
                          : null,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Os documentos herdados de pedidos/reembolsos ficam protegidos contra eliminação nesta galeria.',
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PrimaryDocumentCard extends StatelessWidget {
  const _PrimaryDocumentCard({
    required this.repository,
    required this.document,
    required this.onOpen,
  });

  final FinancialDocumentsRepository repository;
  final Map<String, dynamic> document;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isImage = FinancialDocumentsRepository.isImage(document);
    final label = FinancialDocumentsRepository.documentTypeLabel(
      document['document_type']?.toString(),
    );

    return AspectRatio(
      aspectRatio: 16 / 7,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isImage)
                FutureBuilder<String>(
                  future: repository.signedUrl(document),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return Image.network(snapshot.data!, fit: BoxFit.cover);
                  },
                )
              else
                Container(
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        FinancialDocumentsRepository.isPdf(document)
                            ? Icons.picture_as_pdf_outlined
                            : Icons.description_outlined,
                        size: 64,
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          document['original_file_name']?.toString() ??
                              'Documento',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              Positioned(
                left: 10,
                top: 10,
                child: Chip(
                  avatar: const Icon(Icons.star, size: 17),
                  label: Text('Principal · $label'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: FilledButton.tonalIcon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Abrir'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentThumbnail extends StatelessWidget {
  const _DocumentThumbnail({
    required this.repository,
    required this.document,
    required this.canManage,
    required this.onOpen,
    this.onPrimary,
    this.onDelete,
  });

  final FinancialDocumentsRepository repository;
  final Map<String, dynamic> document;
  final bool canManage;
  final VoidCallback onOpen;
  final VoidCallback? onPrimary;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final primary = document['is_primary'] == true;
    final image = FinancialDocumentsRepository.isImage(document);

    return SizedBox(
      width: 112,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InkWell(
              onTap: onOpen,
              child: image
                  ? FutureBuilder<String>(
                      future: repository.signedUrl(document),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        }
                        return Image.network(snapshot.data!, fit: BoxFit.cover);
                      },
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          FinancialDocumentsRepository.isPdf(document)
                              ? Icons.picture_as_pdf_outlined
                              : Icons.description_outlined,
                          size: 34,
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Text(
                            FinancialDocumentsRepository.documentTypeLabel(
                              document['document_type']?.toString(),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
            ),
            if (primary)
              const Positioned(
                left: 4,
                bottom: 4,
                child: Icon(Icons.star, size: 20),
              ),
            if (document['origin'] == 'request')
              const Positioned(
                left: 4,
                top: 4,
                child: Tooltip(
                  message: 'Herdado do pedido financeiro',
                  child: Icon(Icons.link, size: 20),
                ),
              ),
            if (canManage && (onPrimary != null || onDelete != null))
              Positioned(
                right: 0,
                top: 0,
                child: PopupMenuButton<String>(
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'primary') onPrimary?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (_) => [
                    if (onPrimary != null)
                      const PopupMenuItem(
                        value: 'primary',
                        child: Text('Definir como principal'),
                      ),
                    if (onDelete != null)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Eliminar documento'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
