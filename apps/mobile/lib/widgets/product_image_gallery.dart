import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../repositories/shop_repository.dart';

class ProductImageGallery extends StatefulWidget {
  const ProductImageGallery({
    super.key,
    required this.repository,
    required this.productId,
    required this.coverPath,
    required this.canManage,
    required this.onChanged,
  });

  final ShopRepository repository;
  final String productId;
  final String? coverPath;
  final bool canManage;
  final Future<void> Function() onChanged;

  @override
  State<ProductImageGallery> createState() => _ProductImageGalleryState();
}

class _ProductImageGalleryState extends State<ProductImageGallery> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.repository.productImages(widget.productId);
  }

  Future<void> _refresh() async {
    setState(() {
      _reload();
    });
    await _future;
  }

  Future<void> _addPhotos() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar fotografia'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              subtitle: const Text('Podes selecionar várias fotografias.'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final picker = ImagePicker();
      final files = source == ImageSource.gallery
          ? await picker.pickMultiImage(imageQuality: 85, maxWidth: 1600)
          : <XFile>[
              if (await picker.pickImage(
                    source: ImageSource.camera,
                    imageQuality: 85,
                    maxWidth: 1600,
                  )
                  case final file?)
                file,
            ];
      if (files.isEmpty) return;
      for (final file in files) {
        await widget.repository.uploadProductImage(
          productId: widget.productId,
          file: file,
        );
      }
      await widget.onChanged();
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível carregar as fotografias: $error')),
      );
    }
  }

  Future<void> _setCover(Map<String, dynamic> image) async {
    try {
      await widget.repository.setPrimaryProductImage(
        productId: widget.productId,
        imageId: image['id'].toString(),
        storagePath: image['storage_path'].toString(),
      );
      await widget.onChanged();
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _delete(Map<String, dynamic> image) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar fotografia?'),
        content: const Text('A fotografia será removida do artigo e do armazenamento.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteProductImage(
        productId: widget.productId,
        imageId: image['id'].toString(),
        storagePath: image['storage_path'].toString(),
        wasPrimary: image['is_primary'] == true,
      );
      await widget.onChanged();
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _open(Map<String, dynamic> image) {
    final url = widget.repository.publicImageUrl(image['storage_path']);
    if (url == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 800),
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
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(child: ListTile(title: Text('Erro nas fotografias: ${snapshot.error}')));
        }
        if (!snapshot.hasData) {
          return const AspectRatio(
            aspectRatio: 16 / 7,
            child: Card(child: Center(child: CircularProgressIndicator())),
          );
        }
        final images = snapshot.data!;
        Map<String, dynamic>? cover;
        for (final image in images) {
          if (image['is_primary'] == true) {
            cover = image;
            break;
          }
        }
        cover ??= images.isNotEmpty ? images.first : null;
        final coverUrl = cover == null
            ? widget.repository.publicImageUrl(widget.coverPath)
            : widget.repository.publicImageUrl(cover['storage_path']);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 7,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: coverUrl == null
                    ? InkWell(
                        onTap: widget.canManage ? _addPhotos : null,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, size: 50),
                            SizedBox(height: 8),
                            Text('Adicionar fotografias'),
                          ],
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          InkWell(
                            onTap: cover == null ? null : () => _open(cover!),
                            child: Image.network(coverUrl, fit: BoxFit.cover),
                          ),
                          Positioned(
                            left: 10,
                            top: 10,
                            child: Chip(
                              avatar: const Icon(Icons.star, size: 17),
                              label: const Text('Capa'),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          if (widget.canManage)
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: FilledButton.icon(
                                onPressed: _addPhotos,
                                icon: const Icon(Icons.add_photo_alternate_outlined),
                                label: const Text('Adicionar fotos'),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            if (images.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final image = images[index];
                    final url = widget.repository.publicImageUrl(image['storage_path']);
                    final primary = image['is_primary'] == true;
                    return Stack(
                      children: [
                        InkWell(
                          onTap: () => _open(image),
                          child: Container(
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                width: primary ? 3 : 1,
                                color: primary
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).dividerColor,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: url == null
                                ? const Icon(Icons.broken_image_outlined)
                                : Image.network(url, fit: BoxFit.cover),
                          ),
                        ),
                        if (widget.canManage)
                          Positioned(
                            right: 2,
                            top: 2,
                            child: PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              iconSize: 20,
                              onSelected: (value) {
                                if (value == 'cover') _setCover(image);
                                if (value == 'delete') _delete(image);
                              },
                              itemBuilder: (_) => [
                                if (!primary)
                                  const PopupMenuItem(
                                    value: 'cover',
                                    child: Text('Definir como capa'),
                                  ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Eliminar fotografia'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
