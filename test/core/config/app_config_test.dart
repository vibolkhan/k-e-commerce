import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/config/app_config.dart';
import 'package:k_e_commerce/core/config/bootstrap.dart';

void main() {
  test('defaults to dev with no Supabase keys', () {
    final config = AppConfig.fromEnvironment();
    expect(config.env, AppEnv.dev);
    expect(config.isSupabaseConfigured, isFalse);
  });

  test('parses env names and falls back to dev', () {
    expect(AppEnv.parse('staging'), AppEnv.staging);
    expect(AppEnv.parse('prod'), AppEnv.prod);
    expect(AppEnv.parse('nonsense'), AppEnv.dev);
  });

  test('Supabase is configured only when both values are set', () {
    const urlOnly = AppConfig(
      env: AppEnv.dev,
      supabaseUrl: 'https://x.supabase.co',
      supabaseAnonKey: '',
    );
    const both = AppConfig(
      env: AppEnv.dev,
      supabaseUrl: 'https://x.supabase.co',
      supabaseAnonKey: 'key',
    );
    expect(urlOnly.isSupabaseConfigured, isFalse);
    expect(both.isSupabaseConfigured, isTrue);
  });

  test('bootstrap skips Supabase when unconfigured outside prod', () async {
    await bootstrap(AppConfig.fromEnvironment());
  });

  test('bootstrap refuses to start prod without Supabase', () {
    const prod = AppConfig(
      env: AppEnv.prod,
      supabaseUrl: '',
      supabaseAnonKey: '',
    );
    expect(() => bootstrap(prod), throwsStateError);
  });
}
