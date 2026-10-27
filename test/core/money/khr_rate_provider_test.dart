import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/money/khr_rate_provider.dart';

class _FakeSettings implements SettingsRepository {
  @override
  Future<String?> sameDayCutoff() async => null;

  _FakeSettings(this._read);

  final Future<int?> Function() _read;

  @override
  Future<int?> khrPerUsd() => _read();
}

Future<int> _rateWith(Future<int?> Function() read) {
  final container = ProviderContainer.test(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(_FakeSettings(read)),
    ],
  );
  return container.read(khrRateProvider.future);
}

void main() {
  test('uses the rate from settings', () async {
    expect(await _rateWith(() async => 4050), 4050);
  });

  test('falls back to 4,100 when not set', () async {
    expect(await _rateWith(() async => null), 4100);
  });

  test('falls back to 4,100 when the setting is invalid', () async {
    expect(await _rateWith(() async => 0), 4100);
    expect(await _rateWith(() async => -1), 4100);
  });

  test('falls back to 4,100 when settings cannot be read', () async {
    expect(await _rateWith(() => Future.error(Exception('offline'))), 4100);
  });

  test('offline builds use the default without Supabase', () async {
    final container = ProviderContainer.test();
    expect(
      container.read(settingsRepositoryProvider),
      isA<DefaultSettingsRepository>(),
    );
    expect(await container.read(khrRateProvider.future), 4100);
  });

  test('display value is the default until settings load', () async {
    final container = ProviderContainer.test(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          _FakeSettings(() async => 4000),
        ),
      ],
    );
    expect(container.read(khrRateValueProvider), 4100);
    await container.read(khrRateProvider.future);
    expect(container.read(khrRateValueProvider), 4000);
  });
}
