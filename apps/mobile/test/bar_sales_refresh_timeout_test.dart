import 'dart:async';

import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/repositories/bar_sales_repository.dart';
import 'package:bob_manager_mobile/screens/bar_sales_advanced_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SalesRepo extends BarSalesRepository {
  double stock = 25;
  int productReads = 0;
  int completions = 0;
  bool holdCompletion = false;
  bool blockFirstProducts = false;
  final Completer<List<Map<String, dynamic>>> firstProducts =
      Completer<List<Map<String, dynamic>>>();
  final Completer<Map<String, dynamic>> completion =
      Completer<Map<String, dynamic>>();
  String saleStatus = 'draft';

  @override
  bool get canManage => true;
  @override
  bool get canSelectAccount => false;
  @override
  Future<List<Map<String, dynamic>>> products() async {
    productReads++;
    if (blockFirstProducts && productReads == 1) return firstProducts.future;
    return [
      {
        'id': 'product-1',
        'name': 'ARTIGO TESTE RC1',
        'current_stock': stock,
        'consumption_unit': 'unid.',
        'sale_options': [
          {
            'id': 'option-1',
            'name': 'Unidade',
            'public_price': 5.0,
            'member_price': 5.0,
            'stock_quantity': 1.0,
            'active': true,
          }
        ],
      }
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> presets() async => const [];
  @override
  Future<List<Map<String, dynamic>>> events() async => const [];
  @override
  Future<List<Map<String, dynamic>>> treasuryAccounts() async => const [];
  @override
  Future<List<Map<String, dynamic>>> members() async => const [];
  @override
  Future<List<Map<String, dynamic>>> dinners() async => const [];
  @override
  Future<String> createDraft({
    String sourceMode = 'manual',
    String? customerLabel,
    String customerType = 'public',
    String? memberId,
    String? eventId,
    String? weeklyDinnerId,
    String? notes,
  }) async =>
      'sale-1';

  @override
  Future<Map<String, dynamic>> completeSale({
    required String saleId,
    required List<Map<String, dynamic>> lines,
    required String paymentMethod,
    String customerType = 'public',
    String? memberId,
    String? accountId,
    String? customerLabel,
    String? eventId,
    String? weeklyDinnerId,
    String? notes,
  }) async {
    completions++;
    if (holdCompletion) return completion.future;
    stock--;
    saleStatus = 'completed';
    return {'total': 5.0};
  }

  @override
  Future<List<Map<String, dynamic>>> saleHistory({int limit = 100}) async => [
        {'id': 'sale-1', 'status': saleStatus}
      ];
}

void main() {
  setUp(() {
    AppSession.instance.clear();
  });

  testWidgets('a stuck initial read becomes recoverable instead of spinning',
      (tester) async {
    final repository = _SalesRepo()..blockFirstProducts = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BarSalesAdvancedScreen(
          repository: repository,
          loadTimeout: const Duration(milliseconds: 10),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 11));
    await tester.pump();
    expect(find.text('Atualizar'), findsOneWidget);

    await tester.tap(find.text('Atualizar'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Nova venda'), findsOneWidget);
    expect(repository.productReads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed sale reloads authoritative stock in the same view',
      (tester) async {
    final repository = _SalesRepo();
    await tester.binding.setSurfaceSize(const Size(1000, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BarSalesAdvancedScreen(repository: repository),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('ARTIGO TESTE RC1'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Stock 25'), findsOneWidget);

    await tester.tap(find.byTooltip('Adicionar').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Pagamento'));
    await tester.tap(find.text('Pagamento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar venda'));
    await tester.pumpAndSettle();

    expect(repository.completions, 1);
    expect(repository.productReads, greaterThanOrEqualTo(2));
    await tester.scrollUntilVisible(
      find.text('ARTIGO TESTE RC1'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Stock 24'), findsOneWidget);
    expect(find.textContaining('Venda concluída'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ambiguous completion timeout cannot be submitted twice',
      (tester) async {
    final repository = _SalesRepo()..holdCompletion = true;
    await tester.binding.setSurfaceSize(const Size(1000, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BarSalesAdvancedScreen(
          repository: repository,
          writeTimeout: const Duration(milliseconds: 10),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('ARTIGO TESTE RC1'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byTooltip('Adicionar').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Pagamento'));
    await tester.tap(find.text('Pagamento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar venda'));
    await tester.pump(const Duration(milliseconds: 15));
    await tester.pump();

    expect(repository.completions, 1);
    expect(find.textContaining('Não submetas outra vez'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Pagamento'))
            .onPressed,
        isNull);

    repository
      ..saleStatus = 'completed'
      ..stock = 24;
    await tester.tap(find.text('Verificar estado da venda'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('ARTIGO TESTE RC1'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Stock 24'), findsOneWidget);
    expect(repository.completions, 1);
    expect(tester.takeException(), isNull);
  });
}
