class AppConfig {
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
  static const firebaseVapidKey =
      String.fromEnvironment('FIREBASE_VAPID_KEY');
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

  static void validateForRealMode() {
    if (!hasSupabaseConfiguration) {
      throw const AppConfigurationException(
        'Faltam SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY.',
      );
    }
  }
}

class AppConfigurationException implements Exception {
  const AppConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}
