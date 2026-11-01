class AppConfig {
  static const appEnvValue = String.fromEnvironment('APP_ENV');
  static const otherEnvironmentUrlValue =
      String.fromEnvironment('OTHER_ENV_URL');

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseMessagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const firebaseProjectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const firebaseVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');
  static const firebaseAuthDomain =
      String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const firebaseStorageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const appVersion = String.fromEnvironment('APP_VERSION');

  static bool get hasFirebaseConfiguration =>
      firebaseApiKey.trim().isNotEmpty &&
      firebaseAppId.trim().isNotEmpty &&
      firebaseMessagingSenderId.trim().isNotEmpty &&
      firebaseProjectId.trim().isNotEmpty;

  static const explicitDemoMode = bool.fromEnvironment(
    'DEMO_MODE',
    defaultValue: false,
  );

  static bool get hasSupabaseConfiguration =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;

  // Mantém os testes e repositórios compatíveis quando não existem defines,
  // mas a aplicação mostra um erro de configuração em vez de entrar
  // silenciosamente em demonstração.
  static bool get implicitDemoMode =>
      !explicitDemoMode && !hasSupabaseConfiguration;

  static bool get demoMode => explicitDemoMode || !hasSupabaseConfiguration;

  static AppEnvironment get environment =>
      AppEnvironment.fromValue(appEnvValue);

  static Uri? get otherEnvironmentUri {
    final value = otherEnvironmentUrlValue.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    final host = uri.host.toLowerCase();
    final isLoopback = _isLoopbackHost(host);
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && isLoopback)) {
      return null;
    }
    return uri;
  }

  static String? get configurationError => validateBuildConfiguration(
        appEnv: appEnvValue,
        demoMode: explicitDemoMode,
        supabaseUrl: supabaseUrl,
        publishableKey: supabasePublishableKey,
      );

  /// Checks immutable build settings before Auth or any repository is started.
  static String? validateBuildConfiguration({
    required String appEnv,
    required bool demoMode,
    required String supabaseUrl,
    required String publishableKey,
  }) {
    final normalizedEnv = appEnv.trim().toUpperCase();
    if (normalizedEnv != 'TESTE' && normalizedEnv != 'REAL') {
      return 'APP_ENV tem de ser definido explicitamente como TESTE ou REAL.';
    }

    if (demoMode && normalizedEnv != 'TESTE') {
      return 'DEMO_MODE só pode ser utilizado numa build APP_ENV=TESTE.';
    }

    final hasUrl = supabaseUrl.trim().isNotEmpty;
    final hasKey = publishableKey.trim().isNotEmpty;
    if (hasUrl != hasKey) {
      return 'SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY têm de ser definidos em conjunto.';
    }
    if (demoMode && hasUrl) {
      return 'Uma build de demonstração não pode incluir configuração Supabase.';
    }
    if (!demoMode && !hasUrl) {
      return 'Faltam SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY.';
    }

    if (!hasUrl) return null; // Preview local TESTE explicitamente demo.

    final uri = Uri.tryParse(supabaseUrl.trim());
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      return 'SUPABASE_URL não é um endereço válido.';
    }
    final host = uri.host.toLowerCase();
    final isLoopback = _isLoopbackHost(host);
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && isLoopback)) {
      return 'A API deve utilizar HTTPS; HTTP só é permitido em loopback.';
    }
    if (normalizedEnv == 'REAL' && isLoopback) {
      return 'APP_ENV=REAL não pode apontar para um endereço loopback.';
    }
    return null;
  }

  static bool _isLoopbackHost(String host) =>
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      host == '::1' ||
      host == '0.0.0.0' ||
      host.startsWith('127.');

  static void validateForRealMode() {
    final error = configurationError;
    if (error != null) throw AppConfigurationException(error);
  }
}

enum AppEnvironment {
  test,
  real,
  unconfigured;

  static AppEnvironment fromValue(String value) =>
      switch (value.trim().toUpperCase()) {
        'TESTE' => AppEnvironment.test,
        'REAL' => AppEnvironment.real,
        _ => AppEnvironment.unconfigured,
      };
}

class AppConfigurationException implements Exception {
  const AppConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}
