import 'dart:typed_data';

import 'image_models.dart';

class ImageResult {
  const ImageResult({
    required this.optimized,
    required this.thumbnail,
    required this.originalWidth,
    required this.originalHeight,
    required this.finalWidth,
    required this.finalHeight,
    required this.originalSize,
    required this.optimizedSize,
    required this.sha256,
    required this.format,
  });

  final Uint8List optimized;
  final Uint8List thumbnail;
  final int originalWidth;
  final int originalHeight;
  final int finalWidth;
  final int finalHeight;
  final int originalSize;
  final int optimizedSize;
  final String sha256;
  final ImageOutputFormat format;

  int get thumbnailSize => thumbnail.lengthInBytes;

  double get savedPercentage {
    if (originalSize <= 0) return 0;
    final saved = 1 - (optimizedSize / originalSize);
    return (saved * 100).clamp(0, 100).toDouble();
  }
}
