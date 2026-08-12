import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_config.dart';
import 'screens/login_screen.dart';
import 'screens/password_setup_screen.dart';
import 'screens/shell_screen.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.demoMode) {
    AppConfig.validateForRealMode();
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );
  }

  runApp(const BobManagerApp());
}

class BobManagerApp extends StatelessWidget {
  const BobManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BOB Manager',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'PT'),
      supportedLocales: const [Locale('pt', 'PT'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0C18D2),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF08090D),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      home: const _AppBootstrap(),
    );
  }
}

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  late Future<bool> _restoreFuture;
  StreamSubscription<AuthState>? _authSubscription;
  bool _passwordRecovery = false;

  @override
  void initState() {
    super.initState();
    _restoreFuture = AuthService.instance.restore();
    if (!AppConfig.demoMode) {
      _authSubscription =
          Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        if (!mounted) return;
        setState(() {
          if (state.event == AuthChangeEvent.passwordRecovery) {
            _passwordRecovery = true;
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _passwordCompleted() async {
    if (!mounted) return;
    setState(() {
      _passwordRecovery = false;
      _restoreFuture = AuthService.instance.restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (AppConfig.implicitDemoMode) {
      return const _ConfigurationErrorScreen();
    }

    if (!AppConfig.demoMode &&
        (_passwordRecovery || AuthService.instance.needsPasswordSetup)) {
      return PasswordSetupScreen(
        recovery: _passwordRecovery,
        onCompleted: _passwordCompleted,
      );
    }

    if (AppConfig.explicitDemoMode) {
      return const LoginScreen();
    }

    return FutureBuilder<bool>(
      future: _restoreFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data == true) {
          return const ShellScreen();
        }

        return const LoginScreen();
      },
    );
  }
}

class _ConfigurationErrorScreen extends StatelessWidget {
  const _ConfigurationErrorScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield, size: 64),
                    const SizedBox(height: 12),
                    Text(
                      'BOB MANAGER',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Configuração Supabase em falta',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Executa a aplicação com SUPABASE_URL e '
                      'SUPABASE_PUBLISHABLE_KEY. O modo Demo deixou de ser '
                      'ativado silenciosamente.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const SelectableText(
                      'flutter run -d chrome '
                      '--dart-define=SUPABASE_URL=... '
                      '--dart-define=SUPABASE_PUBLISHABLE_KEY=...',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Para demonstração explícita utiliza '
                      '--dart-define=DEMO_MODE=true.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
