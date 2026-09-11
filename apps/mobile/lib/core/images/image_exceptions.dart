sealed class ImagePipelineException implements Exception {
  const ImagePipelineException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class UnsupportedImageException extends ImagePipelineException {
  const UnsupportedImageException([super.message = 'Formato de imagem não suportado.']);
}

final class ImageTooLargeException extends ImagePipelineException {
  const ImageTooLargeException([super.message = 'A imagem excede o tamanho máximo permitido.']);
}

final class InvalidImageException extends ImagePipelineException {
  const InvalidImageException([super.message = 'O ficheiro selecionado não é uma imagem válida.']);
}

final class ImageProcessingException extends ImagePipelineException {
  const ImageProcessingException([super.message = 'Não foi possível processar a imagem.']);
}
