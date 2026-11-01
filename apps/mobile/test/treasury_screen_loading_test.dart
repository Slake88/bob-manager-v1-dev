import 'dart:async';

import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/repositories/treasury_repository.dart';
import 'package:bob_manager_mobile/screens/treasury_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TreasuryRepository extends TreasuryRepository {
  bool holdMovements = false;
  bool failCostCenters = false;
  bool emptyAccounts = false;
  int accountReads = 0;
  int movementReads = 0;
  final Completer<List<Map<String, dynamic>>> heldMovements =
      Completer<List<Map<String, dynamic>>>();

  @override
  bool get canManageAccounts => true;

  @override
  bool get canCreateMovement => true;

  @override
  bool get canTransfer => true;

  @override
  Future<List<Map<String, dynamic>>> listAccounts() async {
    accountReads++;
    if (emptyAccounts) return const [];
    return [
      {
        'id': 'account-a',
        'name': 'Conta teste',
        'account_type': 'cash',
        'allows_negative': false,
        'balance': 23.0,
        'icon': '€',
      }
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> listMovements() {
    movementReads++;
    if (holdMovements) return heldMovements.future;
    return Future.value(const []);
  }

  @override
  Future<List<Map<String, dynamic>>> listCostCenters() async {
    if (failCostCenters) throw StateError('synthetic HTTP failure');
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> listEventsForMovements() async => const [];

  @override
  Future<Map<String, dynamic>> summary({
    List<Map<String, dynamic>>? accounts,
    List<Map<String, dynamic>>? movements,
  }) async {
    final rows = accounts ?? await listAccounts();
    return {
      'accounts': rows,
      'total_balance': rows.fold<double>(
        0,
        (total, row) => total + ((row['balance'] as num?)?.toDouble() ?? 0),
      ),
      'monthly_income': 0.0,
      'monthly_expense': 0.0,
      'pending_approvals': 0,
      'recent_transactions': const <Map<String, dynamic>>[],
    };
  }
}

class _ModuleSwitchHarness extends StatefulWidget {
  const _ModuleSwitchHarness({required this.repository});

  final TreasuryRepository repository;

  @override
  State<_ModuleSwitchHarness> createState() => _ModuleSwitchHarnessState();
}

class _ModuleSwitchHarnessState extends State<_ModuleSwitchHarness> {
  bool _showTreasury = true;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            TextButton(
              onPressed: () => setState(() => _showTreasury = !_showTreasury),
              child: const Text('Mudar módulo'),
            ),
            Expanded(
              child: _showTreasury
                  ? TreasuryScreen(repository: widget.repository)
                  : const Center(child: Text('Outro módulo')),
            ),
          ],
        ),
      );
}

void main() {
  setUp(() {
    AppSession.instance.clear();
    AppSession.instance.authenticate(
      newProfileId: 'synthetic-profile',
      newClubId: 'synthetic-club',
      newFullName: 'Teste',
      newRole: 'super_admin',
    );
    AppSession.instance
        .applyPermissions(AppPermission.values.map((p) => p.key));
  });

  testWidgets('Resumo apresenta saldos e lê movimentos uma só vez',
      (tester) async {
    final repository = _TreasuryRepository();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TreasuryScreen(repository: repository)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Saldo global'), findsOneWidget);
    expect(find.text('23,00 €'), findsNWidgets(2));
    expect(find.text('Sem movimentos registados.'), findsOneWidget);
    expect(repository.accountReads, 1);
    expect(repository.movementReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Resumo sem contas apresenta estado vazio correto',
      (tester) async {
    final repository = _TreasuryRepository()..emptyAccounts = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TreasuryScreen(repository: repository)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('0,00 €'), findsOneWidget);
    expect(find.text('Sem contas ativas para apresentar.'), findsOneWidget);
    expect(find.text('Sem movimentos registados.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sair e regressar ao módulo volta a carregar sem ficar preso',
      (tester) async {
    final repository = _TreasuryRepository();
    await tester.pumpWidget(MaterialApp(
      home: _ModuleSwitchHarness(repository: repository),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Saldo global'), findsOneWidget);

    await tester.tap(find.text('Mudar módulo'));
    await tester.pumpAndSettle();
    expect(find.text('Outro módulo'), findsOneWidget);
    await tester.tap(find.text('Mudar módulo'));
    await tester.pumpAndSettle();

    expect(find.text('Saldo global'), findsOneWidget);
    expect(find.text('23,00 €'), findsNWidgets(2));
    expect(repository.movementReads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('API com erro termina o loading e oferece nova tentativa',
      (tester) async {
    final repository = _TreasuryRepository()
      ..holdMovements = true
      ..failCostCenters = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TreasuryScreen(
          repository: repository,
          loadTimeout: const Duration(seconds: 10),
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('Não foi possível carregar a Tesouraria.'),
        findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Tentar novamente'), findsOneWidget);

    repository
      ..holdMovements = false
      ..failCostCenters = false;
    repository.heldMovements.complete(const []);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('23,00 €'), findsNWidgets(2));
    expect(repository.movementReads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leitura pendente termina com erro identificável e recuperável',
      (tester) async {
    final repository = _TreasuryRepository()..holdMovements = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TreasuryScreen(
          repository: repository,
          loadTimeout: const Duration(milliseconds: 10),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 11));
    await tester.pump();
    expect(find.textContaining('A leitura de movimentos excedeu 10 ms.'),
        findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(tester.takeException(), isNull);
    repository.heldMovements.complete(const []);
  });

  test('utilizador sem viewTreasury continua impedido de ler contas', () async {
    AppSession.instance.clear();
    AppSession.instance.authenticate(
      newProfileId: 'synthetic-limited-profile',
      newClubId: 'synthetic-club',
      newFullName: 'Membro',
      newRole: 'member',
    );
    AppSession.instance.applyPermissions(const <String>[]);

    await expectLater(
      TreasuryRepository().listAccounts(),
      throwsA(isA<TreasuryUserException>()),
    );
  });

  testWidgets('ecrã não apresenta saldos a membro sem viewTreasury',
      (tester) async {
    AppSession.instance.clear();
    AppSession.instance.authenticate(
      newProfileId: 'synthetic-limited-profile',
      newClubId: 'synthetic-club',
      newFullName: 'Membro',
      newRole: 'member',
    );
    AppSession.instance.applyPermissions(const <String>[]);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: TreasuryScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('23,00 €'), findsNothing);
    expect(find.textContaining('Não foi possível carregar a Tesouraria.'),
        findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
