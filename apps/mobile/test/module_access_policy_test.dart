import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/module_access_policy.dart';
import 'package:bob_manager_mobile/core/module_definition.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/repositories/financial_requests_repository.dart';
import 'package:bob_manager_mobile/repositories/treasury_repository.dart';
import 'package:bob_manager_mobile/screens/module_router.dart';
import 'package:bob_manager_mobile/screens/treasury_module_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AppSession.instance.clear());

  testWidgets('uma rota direta sem consulta mostra acesso negado antes do ecrã',
      (tester) async {
    _authenticate(const [], role: 'member');
    final treasury =
        appModules.firstWhere((module) => module.code == 'treasury');

    await tester.pumpWidget(
      MaterialApp(home: ModuleRouter(module: treasury)),
    );

    expect(
      find.text('Não tem permissão para consultar este módulo.'),
      findsOneWidget,
    );
    expect(find.byType(TreasuryModuleScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('as novas permissões de consulta protegem as rotas diretamente',
      (tester) async {
    const protectedCodes = [
      'dashboard',
      'activity',
      'financial',
      'weekly_officer',
      'agenda',
    ];
    _authenticate(const [], role: 'member');

    for (final code in protectedCodes) {
      final module = appModules.firstWhere((item) => item.code == code);
      await tester.pumpWidget(
        MaterialApp(home: ModuleRouter(module: module)),
      );
      expect(
        find.text('Não tem permissão para consultar este módulo.'),
        findsOneWidget,
        reason: 'A rota $code deve ser recusada antes de montar o ecrã.',
      );
      expect(tester.takeException(), isNull);
    }
  });

  test('as cinco permissões novas são configuráveis e respeitam o bloqueio',
      () {
    const cases = <String, AppPermission>{
      'dashboard': AppPermission.viewDashboard,
      'activity': AppPermission.viewActivity,
      'financial': AppPermission.viewFinancialRequests,
      'weekly_officer': AppPermission.viewWeeklyOfficer,
      'agenda': AppPermission.viewAgenda,
    };
    _authenticate(const [], role: 'member');

    for (final entry in cases.entries) {
      final module = appModules.firstWhere((item) => item.code == entry.key);
      expect(ModuleAccessPolicy.canView(module, AppSession.instance), isFalse);
      AppSession.instance.applyPermissions([entry.value.key]);
      expect(ModuleAccessPolicy.canView(module, AppSession.instance), isTrue);
      AppSession.instance.applyPermissions(const []);
      expect(ModuleAccessPolicy.canView(module, AppSession.instance), isFalse);
    }
  });

  test('hidratação combina defaults, matriz por cargo e override individual',
      () {
    final effective = resolveEffectivePermissionKeys(
      roleKey: 'member',
      roleRows: const [
        {'permission_key': 'viewDashboard', 'allowed': false},
        {'permission_key': 'manageOwnFinancialRequests', 'allowed': true},
        {'permission_key': 'manageWeeklyOfficer', 'allowed': true},
      ],
      userOverrides: const [
        {'permission_key': 'viewDashboard', 'allowed': true},
        {'permission_key': 'viewActivity', 'allowed': false},
        {'permission_key': 'manageOwnFinancialRequests', 'allowed': false},
        {'permission_key': 'manageWeeklyOfficer', 'allowed': false},
      ],
    );
    expect(effective, contains('viewDashboard'));
    expect(effective, isNot(contains('viewActivity')));
    expect(effective, isNot(contains('manageOwnFinancialRequests')));
    expect(effective, isNot(contains('manageWeeklyOfficer')));
    expect(effective, contains('viewAgenda'));
  });

  test('defaults de consulta não autorizam cargos ativos desconhecidos', () {
    for (final permission in [
      AppPermission.viewDashboard,
      AppPermission.viewActivity,
      AppPermission.viewFinancialRequests,
      AppPermission.viewWeeklyOfficer,
      AppPermission.viewAgenda,
      AppPermission.manageOwnFinancialRequests,
    ]) {
      expect(
        permission.defaultAllowedForRole('unrecognized_role'),
        isFalse,
        reason:
            '${permission.key} não deve ser concedida a um cargo desconhecido.',
      );
    }

    final effective = resolveEffectivePermissionKeys(
      roleKey: 'unrecognized_role',
      roleRows: const [],
      userOverrides: const [],
    );
    expect(effective, isEmpty);
  });

  test('permissões novas aparecem na matriz do Super Admin por módulo', () {
    expect(AppPermission.viewDashboard.module, 'Dashboard');
    expect(AppPermission.viewActivity.module, 'Atividade');
    expect(AppPermission.viewFinancialRequests.module, 'Pedidos & Pagamentos');
    expect(AppPermission.approveExpenseRequests.module, 'Pedidos & Pagamentos');
    expect(AppPermission.viewWeeklyOfficer.module, 'Oficial da Semana');
    expect(AppPermission.manageWeeklyOfficer.module, 'Oficial da Semana');
    expect(AppPermission.viewAgenda.module, 'Agenda');
    expect(AppPermission.manageAgenda.module, 'Agenda');
    expect(
      AppPermission.manageOwnFinancialRequests.module,
      'Pedidos & Pagamentos',
    );
    expect(AppPermission.viewDashboard.label, isNotEmpty);
    expect(AppPermission.viewFinancialRequests.label, isNotEmpty);
    expect(
      AppPermission.viewDashboard.defaultAllowedForRole('member'),
      isTrue,
    );
    expect(
      AppPermission.manageOwnFinancialRequests.defaultAllowedForRole('member'),
      isTrue,
    );
    expect(
      AppPermission.manageAgenda.defaultAllowedForRole('member'),
      isFalse,
    );
    expect(
      AppPermission.manageAgenda.defaultAllowedForRole('secretary'),
      isTrue,
    );
  });

  test('consulta e edição própria de pedidos são independentes', () {
    _authenticate(const ['viewFinancialRequests'], role: 'member');
    final requests = FinancialRequestsRepository();
    expect(requests.canManage, isFalse);
    expect(requests.canManageOwnRequests, isFalse);
    expect(requests.canEditOwnRequests, isFalse);

    AppSession.instance.applyPermissions(
      const ['viewFinancialRequests', 'manageOwnFinancialRequests'],
    );
    expect(requests.canManageOwnRequests, isTrue);
    expect(requests.canEditOwnRequests, isTrue);
    expect(requests.canManage, isFalse);
  });

  test('consulta e edição continuam a ser permissões distintas', () {
    _authenticate(const ['viewTreasury'], role: 'member');
    final treasury =
        appModules.firstWhere((module) => module.code == 'treasury');

    expect(ModuleAccessPolicy.canView(treasury, AppSession.instance), isTrue);
    expect(AppSession.instance.can(AppPermission.viewTreasury), isTrue);
    expect(
        AppSession.instance.can(AppPermission.createTreasuryMovement), isFalse);
    expect(AppSession.instance.can(AppPermission.transferBetweenAccounts),
        isFalse);
    expect(AppSession.instance.can(AppPermission.manageFinancialAccounts),
        isFalse);
    final repository = TreasuryRepository();
    expect(repository.canCreateMovement, isFalse);
    expect(repository.canTransfer, isFalse);
    expect(repository.canManageAccounts, isFalse);
  });

  testWidgets(
      'uma rota sem sessão também é recusada sem montar o ecrã protegido',
      (tester) async {
    AppSession.instance.clear();
    final treasury =
        appModules.firstWhere((module) => module.code == 'treasury');
    await tester.pumpWidget(
      MaterialApp(home: ModuleRouter(module: treasury)),
    );

    expect(
      find.text('Não tem permissão para consultar este módulo.'),
      findsOneWidget,
    );
    expect(find.byType(TreasuryModuleScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _authenticate(Iterable<String> permissions, {required String role}) {
  final session = AppSession.instance;
  session.clear();
  session.authenticate(
    newProfileId: 'synthetic-module-access-profile',
    newClubId: 'synthetic-module-access-club',
    newFullName: 'Perfil sintético de acesso',
    newRole: role,
  );
  session.applyPermissions(permissions);
}
