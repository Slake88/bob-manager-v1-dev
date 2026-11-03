import 'package:bob_manager_mobile/repositories/financial_documents_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('categorias financeiras têm rótulos estáveis', () {
    expect(
      FinancialDocumentsRepository.documentTypeLabel('receipt'),
      'Talão / recibo',
    );
    expect(
      FinancialDocumentsRepository.documentTypeLabel('payment_proof'),
      'Comprovativo de pagamento',
    );
    expect(
      FinancialDocumentsRepository.documentTypeLabel('invoice_other'),
      'Fatura / PDF / outro',
    );
  });

  test('reconhece imagens pelo MIME type', () {
    expect(
      FinancialDocumentsRepository.isImage({
        'mime_type': 'image/jpeg',
        'original_file_name': 'talao.jpg',
      }),
      isTrue,
    );
  });

  test('reconhece PDF pelo nome quando MIME type não existe', () {
    expect(
      FinancialDocumentsRepository.isPdf({
        'mime_type': null,
        'original_file_name': 'fatura.PDF',
      }),
      isTrue,
    );
  });

  test('documentos herdados de pedidos não são elimináveis', () {
    expect(
      FinancialDocumentsRepository.isDeletable({
        'origin': 'request',
        'source_attachment_id': 'attachment-id',
      }),
      isFalse,
    );
  });

  test('documentos carregados diretamente são elimináveis', () {
    expect(
      FinancialDocumentsRepository.isDeletable({
        'origin': 'direct',
        'source_attachment_id': null,
      }),
      isTrue,
    );
  });
}
