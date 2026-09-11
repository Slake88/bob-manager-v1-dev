import 'package:bob_manager_mobile/repositories/financial_ocr_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Commit 11 OCR financeiro e Bar', () {
    test('aceita apenas MIME suportado', () {
      expect(FinancialOcrRepository.isSupportedMime('image/jpeg'), isTrue);
      expect(FinancialOcrRepository.isSupportedMime('application/pdf'), isTrue);
      expect(FinancialOcrRepository.isSupportedMime('text/plain'), isFalse);
    });

    test('apresenta estados OCR em português', () {
      expect(FinancialOcrRepository.statusLabel('ready'), 'Pronto para revisão');
      expect(FinancialOcrRepository.statusLabel('unconfigured'), 'OCR por configurar');
      expect(FinancialOcrRepository.statusLabel('confirmed'), 'Confirmado');
    });

    test('extrai linhas estruturadas do job', () {
      final lines = FinancialOcrRepository.lineItems({
        'line_items': [
          {'description': 'Água 6x', 'quantity': 2},
        ],
      });
      expect(lines, hasLength(1));
      expect(lines.first['description'], 'Água 6x');
    });

    test('deteta discrepância de total financeiro', () {
      expect(FinancialOcrRepository.hasAmountDiscrepancy(100, 100.005), isFalse);
      expect(FinancialOcrRepository.hasAmountDiscrepancy(100, 101), isTrue);
    });

    test('sugere artigo por nome normalizado', () {
      final products = <Map<String, dynamic>>[
        {'id': 'beer', 'name': 'Cerveja Super Bock', 'sku': '', 'supplier': ''},
        {'id': 'water', 'name': 'Água 50 cl', 'sku': '', 'supplier': ''},
      ];
      expect(
        FinancialOcrRepository.suggestProductId('CERVEJA SUPER BOCK 20L', products),
        'beer',
      );
      expect(
        FinancialOcrRepository.suggestProductId('Agua 50 CL pack', products),
        'water',
      );
    });

    test('não força associação de linha sem semelhança suficiente', () {
      final products = <Map<String, dynamic>>[
        {'id': 'beer', 'name': 'Cerveja', 'sku': '', 'supplier': ''},
      ];
      expect(
        FinancialOcrRepository.suggestProductId('Guardanapos papel', products),
        isNull,
      );
    });
  });
}
