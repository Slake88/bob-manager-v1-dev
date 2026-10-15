enum ImageOutputFormat {
  jpeg,
  webp,
}

enum ImageCategory {
  cover,
  front,
  back,
  side,
  label,
  detail,
  packaging,
  document,
  other,
}

enum ImageSourceType {
  camera,
  gallery,
  import,
}

class ImageProfile {
  const ImageProfile({
    required this.maxDimension,
    required this.thumbnailDimension,
    required this.quality,
    required this.thumbnailQuality,
    required this.format,
    this.maxInputBytes = 20 * 1024 * 1024,
    this.minimumDimension = 64,
  });

  final int maxDimension;
  final int thumbnailDimension;
  final int quality;
  final int thumbnailQuality;
  final ImageOutputFormat format;
  final int maxInputBytes;
  final int minimumDimension;
}
