import 'package:flutter/material.dart';

String documentFriendlyError(Object error) {
  if (error is StateError) return error.message.toString();
  if (error is ArgumentError) {
    return error.message?.toString() ?? 'Dados inválidos.';
  }
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}

void documentSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

IconData documentIcon(Object? mime) {
  final value = mime?.toString().toLowerCase() ?? '';
  if (value.startsWith('image/')) return Icons.image_outlined;
  if (value == 'application/pdf') return Icons.picture_as_pdf_outlined;
  return Icons.description_outlined;
}

class DocumentErrorView extends StatelessWidget {
  const DocumentErrorView({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(documentFriendlyError(error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
