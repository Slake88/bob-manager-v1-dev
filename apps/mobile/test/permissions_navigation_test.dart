import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/module_access_policy.dart';
import 'package:bob_manager_mobile/core/module_definition.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/screens/login_screen.dart';
import 'package:bob_manager_mobile/screens/module_router.dart';
import 'package:bob_manager_mobile/screens/shell_screen.dart';
import 'package:bob_manager_mobile/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    AppSession.instance.clear();
    PermissionPolicy.reset();
  });

  test('override individual deny prevalece sobre Super Admin e sobre cargo',
      () {
    final permissions = resolveEffectivePermissionKeys(
      superAdmin: true,
      roleRows: const [
        {'permission_key': 'viewTreasury', 'allowed': true},
      ],
      userOverrides: const [
        {'permission_key': 'viewTreasury', 'allowed': false},
      ],
    );

    AppSession.instance.authenticate(
      newProfileId: 'synthetic-super-admin',
      newClubId: 'club-a',
      newFullName: 'Super Admin de teste',
      newRole: 'super_admin',
    );
    AppSession.instance.applyPermissions(permissions);

    expect(AppSession.instance.can(AppPermission.viewTreasury), isFalse);
    expect(AppSession.instance.can(AppPermission.manageSettings), isTrue);
  });

  test('deny individual prevalece sobre allow configurado para a função', () {
    final permissions = resolveEffectivePermissionKeys(
      superAdmin: false,
      roleRows: const [
        {'permission_key': 'viewTreasury', 'allowed': true},
      ],
      userOverrides: const [
        {'permission_key': 'viewTreasury', 'allowed': false},
      ],
    );

    AppSession.instance.authenticate(
      newProfileId: 'synthetic-member',
      newClubId: 'club-a',
      newFullName: 'Membro de teste',
      newRole: 'member',
    );
    AppSession.instance.applyPermissions(permissions);

    expect(AppSession.instance.can(AppPermission.viewTreasury), isFalse);
  });
  test('Super Admin mantém permissões padrão quando não há override', () {
    final permissions = resolveEffectivePermissionKeys(
      superAdmin: true,
      roleRows: const [],
      userOverrides: const [],
    );

    AppSession.instance.authenticate(
      newProfileId: 'synthetic-super-admin',
      newClubId: 'club-a',
      newFullName: 'Super Admin de teste',
      newRole: 'super_admin',
    );
    AppSession.instance.applyPermissions(permissions);

    for (final permission in AppPermission.values) {
      expect(AppSession.instance.can(permission), isTrue,
          reason: permission.name);
    }
  });

  test('as permissões novas controlam os módulos correspondentes', () {
    AppSession.instance.authenticate(
      newProfileId: 'synthetic-member',
      newClubId: 'club-a',
      newFullName: 'Membro de teste',
      newRole: 'member',
    );

    const modulePermissionPairs = <String, String>{
      'dashboard': 'viewDashboard',
      'activity': 'viewActivity',
      'financial': 'viewFinancialRequests',
      'weekly_officer': 'viewWeeklyOfficer',
      'agenda': 'viewAgenda',
    };
    for (final entry in modulePermissionPairs.entries) {
      final module = appModules.singleWhere(
        (item) => item.code == entry.key,
      );
      AppSession.instance.applyPermissions([entry.value]);
      expect(
        ModuleAccessPolicy.canView(module, AppSession.instance),
        isTrue,
        reason: entry.key,
      );
      AppSession.instance.applyPermissions(const []);
      expect(
        ModuleAccessPolicy.canView(module, AppSession.instance),
        isFalse,
        reason: entry.key,
      );
    }
  });
  test('consulta sem edição permite abrir o módulo mas bloqueia edição', () {
    AppSession.instance.authenticate(
      newProfileId: 'synthetic-member',
      newClubId: 'club-a',
      newFullName: 'Membro de teste',
      newRole: 'member',
    );
    AppSession.instance.applyPermissions(const ['viewBar']);

    final bar = appModules.singleWhere((module) => module.code == 'bar');
    expect(ModuleAccessPolicy.canView(bar, AppSession.instance), isTrue);
    expect(AppSession.instance.can(AppPermission.viewBar), isTrue);
    expect(AppSession.instance.can(AppPermission.manageBar), isFalse);
  });

  test('consulta e edição autorizadas são independentes e efetivas', () {
    AppSession.instance.authenticate(
      newProfileId: 'synthetic-manager',
      newClubId: 'club-a',
      newFullName: 'Responsável de teste',
      newRole: 'inventory_manager',
    );
    AppSession.instance.applyPermissions(const ['viewBar', 'manageBar']);

    final bar = appModules.singleWhere((module) => module.code == 'bar');
    expect(ModuleAccessPolicy.canView(bar, AppSession.instance), isTrue);
    expect(AppSession.instance.can(AppPermission.manageBar), isTrue);
  });

  testWidgets('os 17 módulos ficam visíveis e acesso não autorizado é negado',
      (tester) async {
    AppSession.instance.authenticate(
      newProfileId: 'synthetic-member',
      newClubId: 'club-a',
      newFullName: 'Membro de teste',
      newRole: 'member',
    );
    AppSession.instance.applyPermissions(const []);

    tester.view.physicalSize = const Size(1440, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ShellScreen()));
    await tester.pump();

    expect(appModules, hasLength(17));
    for (final module in appModules) {
      expect(find.text(module.title), findsWidgets, reason: module.code);
    }
    expect(
      find.text('Não tem permissão para consultar este módulo'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ModuleRouter(
          module: appModules.singleWhere((module) => module.code == 'treasury'),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Não tem permissão para consultar este módulo'),
      findsOneWidget,
    );
    expect(find.byType(ShellScreen), findsNothing);
  });

  testWidgets(
      'login concluído sem exigir nova password navega para ShellScreen',
      (tester) async {
    Future<void> signInWithoutPasswordSetup(
        String email, String password) async {
      expect(email, 'synthetic@example.test');
      expect(password, 'synthetic-password');
      expect(AuthService.instance.needsPasswordSetup, isFalse);
      AppSession.instance.authenticate(
        newProfileId: 'synthetic-member',
        newClubId: 'club-a',
        newFullName: 'Membro de teste',
        newRole: 'member',
      );
      AppSession.instance.applyPermissions(const []);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(onSignIn: signInWithoutPasswordSetup),
      ),
    );
    await tester.enterText(
      find.byType(TextField).at(0),
      'synthetic@example.test',
    );
    await tester.enterText(find.byType(TextField).at(1), 'synthetic-password');
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(ShellScreen), findsOneWidget);
    expect(
      find.text('Não tem permissão para consultar este módulo'),
      findsOneWidget,
    );
  });
}
