import 'package:bob_manager_mobile/core/app_config.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/repositories/treasury_repository.dart';
import 'package:bob_manager_mobile/repositories/weekly_dinner_finance_repository.dart';
import 'package:bob_manager_mobile/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    AppSession.instance.clear();
    PermissionPolicy.reset();
  });

  test(
    'Tesouraria demo mantém a mesma fixture após seed e recarregamento',
    () async {
      expect(AppConfig.explicitDemoMode, isTrue);

      await AuthService.instance.signInDemo();
      final repository = TreasuryRepository();
      final first = await repository.summary();
      final firstAccounts = List<Map<String, dynamic>>.from(
        first['accounts'] as List,
      );
      final firstBalances = {
        for (final account in firstAccounts)
          account['id'].toString(): account['balance'],
      };

      expect(
        firstAccounts.map((account) => account['name']),
        containsAll([
          'Caixa',
          'Banco CGD',
          'Reserva',
          'Representação',
          'Marketing',
          'Euromilhões',
          'Club House',
          'Caixa BAR Demo',
        ]),
      );
      expect(first['total_balance'], 2930.0);

      await WeeklyDinnerFinanceRepository.seedDemo();
      final afterNavigation = await repository.summary();
      final afterBalances = {
        for (final account in List<Map<String, dynamic>>.from(
            afterNavigation['accounts'] as List))
          account['id'].toString(): account['balance'],
      };
      final movements = await repository.listMovements();

      expect(afterBalances, firstBalances);
      expect(afterNavigation['total_balance'], first['total_balance']);
      expect(
        movements.where((row) => row['description'] == 'Venda de jantar Demo'),
        hasLength(1),
      );
    },
    skip: !AppConfig.explicitDemoMode,
  );
}
