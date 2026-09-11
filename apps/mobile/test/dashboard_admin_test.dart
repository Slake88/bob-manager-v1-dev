import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/repositories/admin_repository.dart';
import 'package:bob_manager_mobile/repositories/dashboard_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppSession.instance.clear());

  test('dashboard consolida indicadores dos módulos', () async {
    final summary = await DashboardRepository().summary();
    expect(summary['members'], greaterThan(0));
    expect(summary['total_balance'], isA<double>());
    expect(summary['fee_outstanding'], isA<double>());
    expect(summary['open_events'], isA<int>());
    expect(summary['low_stock'], isA<int>());
    expect(summary['expiring_documents'], isA<int>());
  });

  test('direção pode consultar e guardar parâmetros', () async {
    final repository = AdminRepository();
    final created = await repository.saveSetting(
      key: 'monthly_fee',
      value: '25',
    );
    expect(created['key'], 'monthly_fee');
    final settings = await repository.listSettings();
    expect(settings.any((row) => row['id'] == created['id']), isTrue);
  });

  test('membro comum não acede à administração', () async {
    AppSession.instance.role = 'Membro';
    expect(
      () => AdminRepository().listSettings(),
      throwsA(isA<StateError>()),
    );
  });

  test('relatório financeiro respeita o cargo', () async {
    AppSession.instance.role = 'Membro';
    var report = await DashboardRepository().reportsSummary();
    expect(report['can_view_financial'], isFalse);

    AppSession.instance.role = 'Tesoureiro';
    report = await DashboardRepository().reportsSummary();
    expect(report['can_view_financial'], isTrue);
  });
}
