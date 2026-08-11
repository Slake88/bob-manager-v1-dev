import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'image_exceptions.dart';
import 'image_models.dart';
import 'image_processor.dart';
import 'image_result.dart';

class DefaultImageProcessor implements ImageProcessor {
  const DefaultImageProcessor();

  @override
  Future<ImageResult> process({
    required XFile file,
    required ImageProfile profile,
  }) async {
    try {
      final originalBytes = await file.readAsBytes();
      final decoded = img.decodeImage(originalBytes);
      if (decoded == null) {
        throw const InvalidImageException('Não foi possível descodificar a imagem.');
      }

      final originalWidth = decoded.width;
      final originalHeight = decoded.height;
      final oriented = img.bakeOrientation(decoded);
      final resized = _fit(oriented, profile.maxDimension);
      final thumbnailImage = _fit(resized, profile.thumbnailDimension);

      // Re-encoding intentionally drops source metadata, including GPS/EXIF.
      final optimized = Uint8List.fromList(
        img.encodeJpg(resized, quality: profile.quality),
      );
      final thumbnail = Uint8List.fromList(
        img.encodeJpg(thumbnailImage, quality: profile.thumbnailQuality),
      );

      return ImageResult(
        optimized: optimized,
        thumbnail: thumbnail,
        originalWidth: originalWidth,
        originalHeight: originalHeight,
        finalWidth: resized.width,
        finalHeight: resized.height,
        originalSize: originalBytes.lengthInBytes,
        optimizedSize: optimized.lengthInBytes,
        sha256: _fnv1a64Hex(optimized),
        format: ImageOutputFormat.jpeg,
      );
    } on ImagePipelineException {
      rethrow;
    } catch (error) {
      throw CompressionFailedException('Falha ao processar a imagem: $error');
    }
  }

  img.Image _fit(img.Image source, int maxDimension) {
    final largest = source.width > source.height ? source.width : source.height;
    if (largest <= maxDimension) return img.Image.from(source);

    if (source.width >= source.height) {
      return img.copyResize(
        source,
        width: maxDimension,
        interpolation: img.Interpolation.cubic,
      );
    }
    return img.copyResize(
      source,
      height: maxDimension,
      interpolation: img.Interpolation.cubic,
    );
  }

  String _fnv1a64Hex(Uint8List bytes) {
    const offset = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    const mask = 0xffffffffffffffff;
    var hash = offset;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
