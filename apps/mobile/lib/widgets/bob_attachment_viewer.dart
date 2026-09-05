import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

class BobAttachmentViewer extends StatefulWidget {
  const BobAttachmentViewer({
    super.key,
    required this.url,
    required this.title,
    this.fileName,
    this.mimeType,
  });

  final String url;
  final String title;
  final String? fileName;
  final String? mimeType;

  static Future<void> open(
    BuildContext context, {
    required String url,
    required String title,
    String? fileName,
    String? mimeType,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => BobAttachmentViewer(
          url: url,
          title: title,
          fileName: fileName,
          mimeType: mimeType,
        ),
      ),
    );
  }

  static bool isImage({String? fileName, String? mimeType}) {
    final mime = mimeType?.trim().toLowerCase() ?? '';
    if (mime.startsWith('image/')) return true;
    final name = fileName?.trim().toLowerCase() ?? '';
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif') ||
        name.endsWith('.bmp');
  }

  static bool isPdf({String? fileName, String? mimeType}) {
    final mime = mimeType?.trim().toLowerCase() ?? '';
    if (mime == 'application/pdf') return true;
    return fileName?.trim().toLowerCase().endsWith('.pdf') == true;
  }

  @override
  State<BobAttachmentViewer> createState() => _BobAttachmentViewerState();
}

class _BobAttachmentViewerState extends State<BobAttachmentViewer> {
  static const double _minScale = 1;
  static const double _maxScale = 5;

  final TransformationController _imageController = TransformationController();
  final GlobalKey<PdfPreviewState> _pdfKey = GlobalKey<PdfPreviewState>();
  TransformationController? _observedPdfController;
  Future<Uint8List>? _pdfBytes;
  double _scale = 1;

  bool get _isImage => BobAttachmentViewer.isImage(
        fileName: widget.fileName,
        mimeType: widget.mimeType,
      );

  bool get _isPdf => BobAttachmentViewer.isPdf(
        fileName: widget.fileName,
        mimeType: widget.mimeType,
      );

  @override
  void initState() {
    super.initState();
    _imageController.addListener(_syncImageScale);
    if (_isPdf) _pdfBytes = _loadBytes(widget.url);
  }

  @override
  void dispose() {
    _imageController.removeListener(_syncImageScale);
    _imageController.dispose();
    _observedPdfController?.removeListener(_syncPdfScale);
    super.dispose();
  }

  Future<Uint8List> _loadBytes(String url) async {
    final data = await NetworkAssetBundle(Uri.parse(url)).load('');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  void _syncImageScale() {
    final value = _imageController.value.getMaxScaleOnAxis();
    _updateScale(value);
  }

  void _syncPdfScale() {
    final controller = _observedPdfController;
    if (controller == null) return;
    _updateScale(controller.value.getMaxScaleOnAxis());
  }

  void _updateScale(double value) {
    if (!mounted || (value - _scale).abs() < 0.01) return;
    setState(() => _scale = value.clamp(_minScale, _maxScale).toDouble());
  }

  TransformationController? get _pdfController =>
      _pdfKey.currentState?.previewWidget.currentState?.transformationController;

  void _bindPdfController() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _pdfController;
      if (controller == null || identical(controller, _observedPdfController)) {
        return;
      }
      _observedPdfController?.removeListener(_syncPdfScale);
      _observedPdfController = controller;
      controller.addListener(_syncPdfScale);
      _syncPdfScale();
    });
  }

  void _setScale(double value) {
    final next = value.clamp(_minScale, _maxScale).toDouble();
    final matrix = next == 1
        ? Matrix4.identity()
        : Matrix4.diagonal3Values(next, next, 1);
    if (_isImage) {
      _imageController.value = matrix;
    } else if (_isPdf) {
      final controller = _pdfController;
      if (controller == null) return;
      controller.value = matrix;
    }
    _updateScale(next);
  }

  void _zoomIn() => _setScale(_scale + 0.5);
  void _zoomOut() => _setScale(_scale - 0.5);
  void _fit() => _setScale(1);

  void _doubleTap() {
    _setScale(_scale > 1.05 ? 1 : 2.5);
  }

  Future<void> _openExternal() async {
    final opened = await launchUrl(
      Uri.parse(widget.url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o ficheiro.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isPdf) _bindPdfController();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(child: _viewer()),
          if (_isImage || _isPdf) _zoomBar(),
        ],
      ),
    );
  }

  Widget _viewer() {
    if (_isImage) {
      return GestureDetector(
        onDoubleTap: _doubleTap,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: InteractiveViewer(
            transformationController: _imageController,
            minScale: _minScale,
            maxScale: _maxScale,
            panEnabled: true,
            scaleEnabled: true,
            child: SizedBox.expand(
              child: Image.network(
                widget.url,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(child: CircularProgressIndicator()),
                errorBuilder: (_, error, __) => _errorView(error),
              ),
            ),
          ),
        ),
      );
    }

    if (_isPdf) {
      return PdfPreview(
        key: _pdfKey,
        build: (_) => _pdfBytes!,
        allowPrinting: false,
        allowSharing: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        dynamicLayout: false,
        enableScrollToPage: true,
        pdfFileName: widget.fileName,
        maxPageWidth: 1100,
        dpi: 144,
        onError: (_, error) => _errorView(error),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_drive_file_outlined, size: 48),
                const SizedBox(height: 12),
                Text(
                  widget.fileName ?? widget.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Este formato não tem pré-visualização interna. Podes abri-lo numa aplicação compatível do dispositivo.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _openExternal,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Abrir no dispositivo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _zoomBar() {
    return SafeArea(
      top: false,
      child: Material(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Diminuir',
                onPressed: _scale <= _minScale + 0.01 ? null : _zoomOut,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  '${(_scale * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Aumentar',
                onPressed: _scale >= _maxScale - 0.01 ? null : _zoomIn,
                icon: const Icon(Icons.add),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Ajustar ao ecrã',
                onPressed: _fit,
                icon: const Icon(Icons.fit_screen_outlined),
              ),
              const SizedBox(width: 8),
              const Tooltip(
                message: 'Usa dois dedos para ampliar e arrasta para navegar. Duplo toque alterna o zoom.',
                child: Icon(Icons.touch_app_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorView(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 10),
            const Text('Não foi possível apresentar o ficheiro.'),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _openExternal,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Abrir no dispositivo'),
            ),
          ],
        ),
      ),
    );
  }
}
