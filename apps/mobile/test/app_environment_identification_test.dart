import 'package:bob_manager_mobile/core/app_config.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/screens/login_screen.dart';
import 'package:bob_manager_mobile/screens/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AppSession.instance.clear());

  group('configuração imutável do ambiente', () {
    test('ambiente em falta nunca é interpretado como REAL', () {
      expect(AppEnvironment.fromValue(''), AppEnvironment.unconfigured);
      expect(
        AppConfig.validateBuildConfiguration(
          appEnv: '',
          demoMode: false,
          supabaseUrl: 'https://test.example.supabase.co',
          publishableKey: 'public-test-key',
        ),
        contains('APP_ENV'),
      );
    });

    test('preview local TESTE explícito é aceite em modo de demonstração', () {
      expect(
        AppConfig.validateBuildConfiguration(
          appEnv: 'TESTE',
          demoMode: true,
          supabaseUrl: '',
          publishableKey: '',
        ),
        isNull,
      );
    });

    test('TESTE pode usar HTTP apenas em loopback', () {
      expect(
        AppConfig.validateBuildConfiguration(
          appEnv: 'TESTE',
          demoMode: false,
          supabaseUrl: 'http://127.0.0.1:19402',
          publishableKey: 'local-public-test-key',
        ),
        isNull,
      );
      expect(
        AppConfig.validateBuildConfiguration(
          appEnv: 'TESTE',
          demoMode: false,
          supabaseUrl: 'http://api.example.test',
          publishableKey: 'local-public-test-key',
        ),
        contains('HTTPS'),
      );
    });

    test('REAL exige API HTTPS e rejeita DEMO_MODE e loopback', () {
      String? validate({required bool demo, required String url}) =>
          AppConfig.validateBuildConfiguration(
            appEnv: 'REAL',
            demoMode: demo,
            supabaseUrl: url,
            publishableKey: 'public-test-key',
          );

      expect(validate(demo: false, url: 'https://real.example.supabase.co'),
          isNull);
      expect(validate(demo: true, url: ''), contains('DEMO_MODE'));
      expect(validate(demo: false, url: 'http://127.0.0.1:19402'),
          contains('loopback'));
      expect(validate(demo: false, url: 'https://localhost'),
          contains('loopback'));
    });

    test('URL e chave pública têm de ser fornecidas em conjunto', () {
      expect(
        AppConfig.validateBuildConfiguration(
          appEnv: 'TESTE',
          demoMode: false,
          supabaseUrl: 'https://test.example.supabase.co',
          publishableKey: '',
        ),
        contains('em conjunto'),
      );
    });
  });

  testWidgets('login apresenta o rótulo TESTE da build', (tester) async {
    expect(AppConfig.environment, AppEnvironment.test);
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('AMBIENTE DE TESTES'), findsOneWidget);
    expect(find.text('BOB REAL · VERSÃO OFICIAL'), findsNothing);
  });

  testWidgets('Shell apresenta o rótulo TESTE durante a utilização',
      (tester) async {
    expect(AppConfig.environment, AppEnvironment.test);
    AppSession.instance.authenticate(
      newProfileId: 'environment-test-profile',
      newClubId: 'environment-test-club',
      newFullName: 'Utilizador sintético',
      newRole: 'member',
    );

    await tester.pumpWidget(const MaterialApp(home: ShellScreen()));
    await tester.pump();
    expect(find.text('AMBIENTE DE TESTES'), findsOneWidget);
    expect(find.text('BOB REAL · VERSÃO OFICIAL'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
