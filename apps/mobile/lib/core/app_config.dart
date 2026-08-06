class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

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
