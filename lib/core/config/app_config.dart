import 'firebase_config.dart';

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
    this.googleWebClientId = '',
    this.googleIosClientId = '',
    this.firebase = const FirebaseConfig(),
  });

  factory AppConfig.fromEnvironment() => AppConfig(
    env: AppEnv.parse(const String.fromEnvironment('APP_ENV')),
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    googleWebClientId: const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    googleIosClientId: const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
    firebase: FirebaseConfig.fromEnvironment(),
  );

  final AppEnv env;
  final String supabaseUrl;
  final String supabaseAnonKey;

  /// OAuth client ids for native Google sign-in (AUTH-02). The web id is the
  /// "server client id" Supabase verifies tokens against; empty disables the
  /// native flow and falls back to the browser.
  final String googleWebClientId;
  final String googleIosClientId;

  /// Push (FCM). Without it the inbox and in-app banners still work.
  final FirebaseConfig firebase;

  /// Push needs Firebase for this platform and a backend to register with.
  bool get isPushConfigured =>
      isSupabaseConfigured && firebase.currentOptions != null;

  bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  bool get isProd => env == AppEnv.prod;

  /// Deep link Supabase returns to after browser-based OAuth on mobile.
  static const authCallbackUrl = 'kshop://login-callback';
}
