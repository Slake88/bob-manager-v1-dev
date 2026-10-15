import 'package:bob_manager_mobile/core/app_role.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/core/treasury_economics.dart';
import 'package:bob_manager_mobile/screens/treasury_operational_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(PermissionPolicy.reset);

  test('saldo pendente nunca fica negativo', () {
    expect(
      treasuryOutstanding({
        'amount': 100,
        'settled_amount': 35,
      }),
      65,
    );
    expect(
      treasuryOutstanding({
        'amount': 100,
        'settled_amount': 120,
      }),
      0,
    );
  });

  test('movimento revertido deixa de contar como movimento económico efetivo', () {
    final rows = <Map<String, dynamic>>[
      {
        'id': 'original',
        'kind': 'expense',
        'amount': 100,
        'reversal_of': null,
      },
      {
        'id': 'reversal',
        'kind': 'income',
        'amount': 100,
        'reversal_of': 'original',
      },
      {
        'id': 'normal',
        'kind': 'expense',
        'amount': 25,
        'reversal_of': null,
      },
    ];

    final effective = effectiveTreasuryRows(rows);
    expect(effective.map((row) => row['id']), ['normal']);
  });

  test('tesoureiro gere caixa mas não aprova a própria diferença por defeito', () {
    expect(
      PermissionPolicy.allows(
        AppRole.treasurer,
        AppPermission.manageTreasuryPlanning,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.treasurer,
        AppPermission.manageCashSessions,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.treasurer,
        AppPermission.approveCashDifferences,
      ),
      isFalse,
    );
  });

  testWidgets('hub operacional abre em Demo sem Supabase', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: TreasuryOperationalScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tesouraria operacional'), findsOneWidget);
    expect(find.text('Contas a pagar'), findsOneWidget);
    expect(find.text('Contas a receber'), findsOneWidget);
    expect(find.text('Orçamentos'), findsOneWidget);
    expect(find.text('Reconciliação'), findsOneWidget);
    expect(find.text('Sessões de caixa'), findsOneWidget);
    expect(find.text('Centros de custo'), findsOneWidget);
    expect(find.text('Reversões'), findsOneWidget);
    expect(find.textContaining('Supabase.instance'), findsNothing);
    expect(find.textContaining('Assertion failed'), findsNothing);
  });
}
