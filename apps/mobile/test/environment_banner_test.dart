import 'package:bob_manager_mobile/core/app_config.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/screens/login_screen.dart';
import 'package:bob_manager_mobile/screens/shell_screen.dart';
import 'package:bob_manager_mobile/services/auth_service.dart';
import 'package:bob_manager_mobile/widgets/environment_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    AppSession.instance.clear();
    PermissionPolicy.reset();
  });

  testWidgets('identificação de ambiente adapta-se a desktop e mobile',
      (tester) async {
    final expectedLabel = switch (AppConfig.environment) {
      AppEnvironment.test => 'AMBIENTE DE TESTES',
      AppEnvironment.real => 'BOB REAL · VERSÃO OFICIAL',
      AppEnvironment.unconfigured => 'AMBIENTE NÃO CONFIGURADO',
    };

    for (final size in [const Size(1366, 768), const Size(360, 800)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Tesouraria'),
              bottom: const EnvironmentBanner(appBarStrip: true),
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );

      expect(find.text(expectedLabel), findsOneWidget);
      expect(
        find.text('AMBIENTE DE TESTES'),
        AppConfig.environment == AppEnvironment.test
            ? findsOneWidget
            : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('login distingue DEMO de BOB TESTE', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('AMBIENTE DE TESTES'), findsOneWidget);
    expect(find.text('MODO DEMONSTRAÇÃO'), findsOneWidget);
  },
      skip: AppConfig.environment != AppEnvironment.test ||
          !AppConfig.explicitDemoMode);

  testWidgets('Shell mantém o aviso amarelo após navegação em desktop e mobile',
      (tester) async {
    await AuthService.instance.signInDemo();
    for (final size in [const Size(1366, 900), const Size(360, 800)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const MaterialApp(home: ShellScreen()));
      await tester.pumpAndSettle();

      expect(find.text('AMBIENTE DE TESTES'), findsOneWidget);
      expect(tester.takeException(), isNull);

      if (size.width > 1000) {
        await tester.tap(find.text('Tesouraria').first);
        await tester.pumpAndSettle();
        expect(find.text('AMBIENTE DE TESTES'), findsOneWidget);
        await tester.pump(const Duration(seconds: 31));
        expect(tester.takeException(), isNull);
      }
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  },
      skip: AppConfig.environment != AppEnvironment.test ||
          !AppConfig.explicitDemoMode);
}
