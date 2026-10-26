import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/l10n/locale_controller.dart';
import 'package:k_e_commerce/core/l10n/locale_store.dart';

class _FakeAccountSync implements LocaleAccountSync {
  final signIns = StreamController<String?>.broadcast();
  final saved = <String>[];

  @override
  Stream<String?> get signedIn => signIns.stream;

  @override
  Future<void> save(String code) async => saved.add(code);
}

void main() {
  late MemoryLocaleStore store;
  late _FakeAccountSync account;

  ProviderContainer containerWith(String? saved) {
    store = MemoryLocaleStore(saved);
    account = _FakeAccountSync();
    return ProviderContainer.test(
      overrides: [
        localeStoreProvider.overrideWithValue(store),
        localeAccountSyncProvider.overrideWithValue(account),
      ],
    );
  }

  test('follows the device until a language is chosen', () {
    final container = containerWith(null);
    expect(container.read(localeControllerProvider), isNull);
  });

  test('loads the saved language', () {
    final container = containerWith('km');
    expect(container.read(localeControllerProvider), const Locale('km'));
  });

  test('ignores a saved language the app does not ship', () {
    final container = containerWith('fr');
    expect(container.read(localeControllerProvider), isNull);
  });

  test('setLocale switches, saves on the device and the account', () async {
    final container = containerWith(null);
    await container
        .read(localeControllerProvider.notifier)
        .setLocale(const Locale('km', 'KH'));
    expect(container.read(localeControllerProvider), const Locale('km'));
    expect(store.read(), 'km');
    expect(account.saved, ['km']);
  });

  test('setLocale ignores unsupported languages', () async {
    final container = containerWith('en');
    await container
        .read(localeControllerProvider.notifier)
        .setLocale(const Locale('fr'));
    expect(container.read(localeControllerProvider), const Locale('en'));
    expect(account.saved, isEmpty);
  });

  test("on sign-in the account's language wins", () async {
    final container = containerWith('en');
    container.read(localeControllerProvider);
    account.signIns.add('km');
    await pumpEventQueue();
    expect(container.read(localeControllerProvider), const Locale('km'));
    expect(store.read(), 'km');
  });

  test(
    'on sign-in without a saved language, the device choice is uploaded',
    () async {
      final container = containerWith('km');
      container.read(localeControllerProvider);
      account.signIns.add(null);
      await pumpEventQueue();
      expect(container.read(localeControllerProvider), const Locale('km'));
      expect(account.saved, ['km']);
    },
  );
}
