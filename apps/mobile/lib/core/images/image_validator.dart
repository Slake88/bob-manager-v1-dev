import 'package:image_picker/image_picker.dart';

import 'image_exceptions.dart';
import 'image_models.dart';

class ImageValidator {
  const ImageValidator();

  static const _supportedExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  Future<void> validate({
    required XFile file,
    required ImageProfile profile,
  }) async {
    final name = file.name.trim().toLowerCase();
    final dot = name.lastIndexOf('.');
    final extension = dot >= 0 ? name.substring(dot + 1) : '';
    if (!_supportedExtensions.contains(extension)) {
      throw const UnsupportedImageException();
    }

    final length = await file.length();
    if (length <= 0) {
      throw const InvalidImageException();
    }
    if (length > profile.maxInputBytes) {
      throw ImageTooLargeException(
        'A imagem excede o limite de ${(profile.maxInputBytes / 1024 / 1024).round()} MB.',
      );
    }
  }
}
