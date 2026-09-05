import 'package:image_picker/image_picker.dart';

import 'image_models.dart';
import 'image_processor.dart';
import 'image_result.dart';
import 'image_validator.dart';

class ImagePipelineService {
  const ImagePipelineService({
    required ImageProcessor processor,
    ImageValidator validator = const ImageValidator(),
  })  : _processor = processor,
        _validator = validator;

  final ImageProcessor _processor;
  final ImageValidator _validator;

  Future<ImageResult> process({
    required XFile file,
    required ImageProfile profile,
  }) async {
    await _validator.validate(file: file, profile: profile);
    return _processor.process(file: file, profile: profile);
  }
}
