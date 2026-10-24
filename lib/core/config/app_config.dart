/// Deployment environment, chosen at build time with `--dart-define`.
enum AppEnv {
  dev,
  staging,
  prod;

  static AppEnv parse(String value) => AppEnv.values.firstWhere(
    (env) => env.name == value,
    orElse: () => AppEnv.dev,
  );
}

/// Build-time configuration. Values come from `--dart-define` or
/// `--dart-define-from-file=config/<env>.json`; secrets are never committed.
class AppConfig {
  const AppConfig({
    required this.env,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  factory AppConfig.fromEnvironment() => AppConfig(
    env: AppEnv.parse(const String.fromEnvironment('APP_ENV')),
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  final AppEnv env;
  final String supabaseUrl;
  final String supabaseAnonKey;

  bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  bool get isProd => env == AppEnv.prod;
}
