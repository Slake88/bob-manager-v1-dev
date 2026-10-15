import 'image_models.dart';

abstract final class ImageProfiles {
  static const generic = ImageProfile(
    maxDimension: 1600,
    thumbnailDimension: 300,
    quality: 85,
    thumbnailQuality: 75,
    format: ImageOutputFormat.webp,
  );

  static const product = ImageProfile(
    maxDimension: 1600,
    thumbnailDimension: 300,
    quality: 85,
    thumbnailQuality: 75,
    format: ImageOutputFormat.webp,
  );

  static const member = ImageProfile(
    maxDimension: 1200,
    thumbnailDimension: 256,
    quality: 85,
    thumbnailQuality: 75,
    format: ImageOutputFormat.webp,
  );

  static const event = ImageProfile(
    maxDimension: 1920,
    thumbnailDimension: 400,
    quality: 85,
    thumbnailQuality: 75,
    format: ImageOutputFormat.webp,
  );

  static const document = ImageProfile(
    maxDimension: 2000,
    thumbnailDimension: 320,
    quality: 88,
    thumbnailQuality: 78,
    format: ImageOutputFormat.jpeg,
  );
}
