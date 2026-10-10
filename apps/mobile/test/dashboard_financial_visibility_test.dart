import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/repositories/dashboard_repository.dart';
import 'package:bob_manager_mobile/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SummaryRepository extends DashboardRepository {
  _SummaryRepository(this.data);

  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> summary() async => data;
}

Map<String, dynamic> summary({bool? canViewFinancial}) => {
      if (canViewFinancial != null) 'can_view_financial': canViewFinancial,
      'members': 10,
      'prospects': 2,
      'total_balance': 1234.0,
      'fee_outstanding': 300.0,
      'monthly_income': 700.0,
      'monthly_expense': 200.0,
      'open_events': 3,
      'low_stock': 1,
      'expiring_documents': 2,
      'pending_approvals': 0,
      'overdue_fees': 1,
    };

Future<void> showDashboard(
  WidgetTester tester,
  Map<String, dynamic> data,
) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DashboardScreen(repository: _SummaryRepository(data)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void expectFinancialVisibility(bool visible) {
  final expected = visible ? findsOneWidget : findsNothing;
  expect(find.text('Saldo total'), expected);
  expect(find.text('Quotas pendentes'), expected);
  expect(find.text('Resultado do mês'), expected);
  expect(find.textContaining('Receitas:'), expected);
  expect(find.textContaining('Despesas:'), expected);
  expect(find.text('Membros ativos'), findsOneWidget);
  expect(find.text('Eventos abertos'), findsOneWidget);
  expect(find.text('Alertas prioritários'), findsOneWidget);
}

void main() {
  setUp(() => AppSession.instance.clear());
  tearDown(() => AppSession.instance.clear());

  testWidgets('member não vê indicadores financeiros com flag false',
      (tester) async {
    AppSession.instance.role = 'member';
    await showDashboard(tester, summary(canViewFinancial: false));
    expectFinancialVisibility(false);
    expect(tester.takeException(), isNull);
  });

  for (final role in ['treasurer', 'admin']) {
    testWidgets('$role vê os indicadores financeiros com flag true',
        (tester) async {
      AppSession.instance.role = role;
      await showDashboard(tester, summary(canViewFinancial: true));
      expectFinancialVisibility(true);
      expect(find.textContaining('700,00'), findsOneWidget);
      expect(find.textContaining('200,00'), findsOneWidget);
      expect(find.textContaining('500,00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('flag do RPC prevalece sobre o role', (tester) async {
    AppSession.instance.role = 'admin';
    await showDashboard(tester, summary(canViewFinancial: false));
    expectFinancialVisibility(false);
    AppSession.instance.role = 'member';
    await showDashboard(tester, summary(canViewFinancial: true));
    expectFinancialVisibility(true);
    expect(tester.takeException(), isNull);
  });

  for (final flag in [false, null]) {
    testWidgets('flag $flag oculta finanças sem exigir valores financeiros',
        (tester) async {
      final data = summary(canViewFinancial: flag)
        ..remove('total_balance')
        ..remove('fee_outstanding')
        ..remove('monthly_income')
        ..remove('monthly_expense');
      await showDashboard(tester, data);
      expectFinancialVisibility(false);
      expect(tester.takeException(), isNull);
    });
  }
}
