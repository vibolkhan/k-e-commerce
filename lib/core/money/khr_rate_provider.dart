import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/bootstrap.dart';
import '../utils/log.dart';
import 'money_format.dart';

/// Reads app-wide settings the client needs for display.
abstract interface class SettingsRepository {
  /// Riel per US dollar, or null when not set.
  Future<int?> khrPerUsd();

  /// Same-day delivery cut-off as "HH:mm" Phnom Penh time, or null.
  Future<String?> sameDayCutoff();
}

/// Offline builds and tests: nothing configured, so defaults apply.
class DefaultSettingsRepository implements SettingsRepository {
  const DefaultSettingsRepository();

  @override
  Future<int?> khrPerUsd() async => null;

  @override
  Future<String?> sameDayCutoff() async => null;
}

/// `app_settings` (key text primary key, value jsonb), readable by everyone
/// and written by admins (F04 / F14). The rate lives under [khrRateKey].
class SupabaseSettingsRepository implements SettingsRepository {
  SupabaseSettingsRepository(this._client);

  static const khrRateKey = 'khr_per_usd';
  static const cutoffKey = 'same_day_cutoff';
  final SupabaseClient _client;

  Future<Object?> _value(String key) async {
    final row = await _client
        .from('app_settings')
        .select('value')
        .eq('key', key)
        .maybeSingle();
    return row?['value'];
  }

  @override
  Future<String?> sameDayCutoff() async => switch (await _value(cutoffKey)) {
    final String s => s,
    _ => null,
  };

  @override
  Future<int?> khrPerUsd() async {
    return switch (await _value(khrRateKey)) {
      final num n => n.round(),
      final String s => num.tryParse(s)?.round(),
      _ => null,
    };
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  if (!ref.watch(appConfigProvider).isSupabaseConfigured) {
    return const DefaultSettingsRepository();
  }
  return SupabaseSettingsRepository(Supabase.instance.client);
});

/// The KHR rate from settings; [kDefaultKhrRate] if it is missing, invalid or
/// can't be read.
final khrRateProvider = FutureProvider<int>((ref) async {
  try {
    final rate = await ref.watch(settingsRepositoryProvider).khrPerUsd();
    if (rate != null && rate > 0) return rate;
  } catch (e) {
    log('Could not load KHR rate, using $kDefaultKhrRate: $e');
  }
  return kDefaultKhrRate;
});

/// The rate to display right now: the default until settings load.
final khrRateValueProvider = Provider<int>(
  (ref) => ref.watch(khrRateProvider).value ?? kDefaultKhrRate,
);
