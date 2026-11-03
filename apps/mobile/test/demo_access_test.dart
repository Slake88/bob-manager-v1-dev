import 'package:bob_manager_mobile/core/app_config.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/screens/login_screen.dart';
import 'package:bob_manager_mobile/screens/shell_screen.dart';
import 'package:bob_manager_mobile/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  tearDown(() {
    AppSession.instance.clear();
    PermissionPolicy.reset();
  });

  testWidgets('entrada demo só aparece com DEMO_MODE explícito',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    if (AppConfig.explicitDemoMode) {
      expect(find.text('MODO DEMONSTRAÇÃO'), findsOneWidget);
      expect(find.text('Entrar em demonstração'), findsOneWidget);

      await tester.tap(find.text('Entrar em demonstração'));
      await tester.pumpAndSettle();

      expect(find.byType(ShellScreen), findsOneWidget);
      expect(AppSession.instance.authenticated, isTrue);
      expect(AppSession.instance.superAdmin, isTrue);
      expect(AppSession.instance.can(AppPermission.viewDashboard), isTrue);
      expect(AppSession.instance.can(AppPermission.manageSettings), isTrue);
    } else {
      expect(find.text('Entrar em demonstração'), findsNothing);
      expect(find.text('Entrar'), findsOneWidget);
      expect(AppSession.instance.authenticated, isFalse);
    }
  });

  test('AuthService recusa entrada demo sem DEMO_MODE explícito', () async {
    if (AppConfig.explicitDemoMode) return;

    await expectLater(
      AuthService.instance.signInDemo(),
      throwsA(isA<AuthException>()),
    );
    expect(AppSession.instance.authenticated, isFalse);
  });
}
