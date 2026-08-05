class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY', defaultValue: '');
  static bool get demoMode => supabaseUrl.isEmpty || supabasePublishableKey.isEmpty;
}
