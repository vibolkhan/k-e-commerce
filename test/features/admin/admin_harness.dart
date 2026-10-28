import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/app.dart';
import 'package:k_e_commerce/core/config/app_config.dart';
import 'package:k_e_commerce/core/config/bootstrap.dart';
import 'package:k_e_commerce/core/router/app_router.dart';
import 'package:k_e_commerce/core/time/phnom_penh_time.dart';
import 'package:k_e_commerce/features/admin/data/admin_repository.dart';
import 'package:k_e_commerce/features/auth/presentation/auth_providers.dart';

import '../../helpers.dart';
import '../auth/fake_auth_repository.dart';
import 'fakes.dart';

const desktop = Size(1440, 900);
const phone = Size(390, 844);

/// The whole app, signed in as [email] (one of [staffAccounts]), opened at
/// [location]. [overrides] swap in more fakes (e.g. the catalogue, F09).
Future<ProviderContainer> pumpAdmin(
  WidgetTester tester, {
  required String email,
  Size size = desktop,
  String? location,
  FakeAdminRepository? admin,
  FakeAuthRepository? auth,
  DateTime? now,
  List<Override> overrides = const [],
}) async {
  setViewSize(tester, size);
  final repo = auth ?? FakeAuthRepository(accounts: {...staffAccounts});
  addTearDown(repo.dispose);
  await repo.signInWithPassword(email, 'password123');
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(env: AppEnv.dev, supabaseUrl: '', supabaseAnonKey: ''),
      ),
      onboardedDevice,
      authRepositoryProvider.overrideWithValue(repo),
      adminRepositoryProvider.overrideWithValue(admin ?? FakeAdminRepository()),
      clockProvider.overrideWithValue(() => now ?? adminNow),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const KApp()),
  );
  await tester.pumpAndSettle();
  if (location != null) {
    container.read(routerProvider).go(location);
    await tester.pumpAndSettle();
  }
  return container;
}
