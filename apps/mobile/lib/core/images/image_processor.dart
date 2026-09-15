import 'package:image_picker/image_picker.dart';

import 'image_models.dart';
import 'image_result.dart';

abstract interface class ImageProcessor {
  Future<ImageResult> process({
    required XFile file,
    required ImageProfile profile,
  });
}
