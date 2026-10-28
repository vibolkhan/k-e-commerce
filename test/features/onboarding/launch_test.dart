import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/app.dart';
import 'package:k_e_commerce/core/config/app_config.dart';
import 'package:k_e_commerce/core/config/bootstrap.dart';
import 'package:k_e_commerce/core/l10n/locale_store.dart';
import 'package:k_e_commerce/core/router/app_role.dart';
import 'package:k_e_commerce/core/router/app_router.dart';
import 'package:k_e_commerce/features/admin/domain/staff_role.dart';
import 'package:k_e_commerce/features/auth/domain/profile.dart';
import 'package:k_e_commerce/features/auth/presentation/auth_providers.dart';
import 'package:k_e_commerce/features/onboarding/data/onboarding_store.dart';
import 'package:k_e_commerce/features/onboarding/presentation/splash_page.dart';

import '../../helpers.dart';
import '../auth/fake_auth_repository.dart';

/// Holds the profile back until [release], like a slow network at launch.
class _SlowAuthRepository extends FakeAuthRepository {
  _SlowAuthRepository({super.accounts});

  final _gate = Completer<void>();
  void release() => _gate.complete();

  @override
  Future<Profile?> fetchProfile() async {
    await _gate.future;
    return super.fetchProfile();
  }
}

/// The seeded test users, one per role.
final _users = {
  'customer@k.example': const Profile(
    id: 'c',
    role: AppRole.customer,
    fullName: 'Dara Sok',
  ),
  'business@k.example': const Profile(
    id: 'b',
    role: AppRole.business,
    fullName: 'Sokha Chan',
  ),
  'rider@k.example': const Profile(
    id: 'r',
    role: AppRole.rider,
    fullName: 'Vuthy Kim',
  ),
  'staff@k.example': const Profile(
    id: 's',
    role: AppRole.admin,
    fullName: 'Chenda Lim',
    staffRole: StaffRole.superAdmin,
    staffStatus: StaffStatus.active,
  ),
};

void main() {
  late MemoryOnboardingStore onboarding;
  late MemoryLocaleStore locale;

  Future<ProviderContainer> launch(
    WidgetTester tester, {
    FakeAuthRepository? auth,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = auth ?? FakeAuthRepository(accounts: {..._users});
    addTearDown(repo.dispose);
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            env: AppEnv.dev,
            supabaseUrl: '',
            supabaseAnonKey: '',
          ),
        ),
        authRepositoryProvider.overrideWithValue(repo),
        onboardingStoreProvider.overrideWithValue(onboarding),
        localeStoreProvider.overrideWithValue(locale),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const KApp()),
    );
    if (settle) await tester.pumpAndSettle();
    return container;
  }

  setUp(() {
    onboarding = MemoryOnboardingStore();
    locale = MemoryLocaleStore();
  });

  group('first launch (F0)', () {
    testWidgets('language → three intro slides → guest Customer Home', (
      tester,
    ) async {
      await launch(tester);
      expect(find.text('Choose your language'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(locale.read(), 'en', reason: 'the preselected language is saved');
      expect(find.text('Everything you need, in one app'), findsOneWidget);
      expect(find.bySemanticsLabel('Slide 1 of 3'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Pay your way'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Same-day delivery'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);

      await tester.tap(find.text('Start shopping'));
      await tester.pumpAndSettle();
      expect(storeHome('customer'), findsOneWidget);
      expect(onboarding.isDone(OnboardingStep.intro), isTrue);
    });

    testWidgets('picking Khmer switches the language before Continue', (
      tester,
    ) async {
      await launch(tester);
      await tester.tap(find.text('Khmer'));
      await tester.pumpAndSettle();
      // Still on S-02 until Continue, now in Khmer.
      expect(find.text('ជ្រើសរើសភាសារបស់អ្នក'), findsOneWidget);
      await tester.tap(find.text('បន្ត'));
      await tester.pumpAndSettle();
      expect(find.text('រំលង'), findsOneWidget); // Skip, on S-03
      expect(locale.read(), 'km');
    });

    testWidgets('Skip goes straight to the home', (tester) async {
      onboarding = MemoryOnboardingStore([OnboardingStep.language]);
      await launch(tester);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(storeHome('customer'), findsOneWidget);
    });

    testWidgets('the next launch opens the home directly', (tester) async {
      onboarding = MemoryOnboardingStore.done();
      await launch(tester);
      expect(find.text('Choose your language'), findsNothing);
      expect(storeHome('customer'), findsOneWidget);
    });

    testWidgets('a restored rider session skips the shopping intro', (
      tester,
    ) async {
      onboarding = MemoryOnboardingStore([OnboardingStep.language]);
      final repo = FakeAuthRepository(accounts: {..._users});
      await repo.signInWithPassword('rider@k.example', 'password123');
      await launch(tester, auth: repo);
      expect(find.text('Rider home'), findsOneWidget);
    });
  });

  group('role routing', () {
    setUp(() => onboarding = MemoryOnboardingStore.done());

    for (final MapEntry(key: email, value: user) in _users.entries) {
      final home = switch (user.role) {
        AppRole.customer => storeHome('customer'),
        AppRole.business => storeHome('business'),
        AppRole.rider => find.text('Rider home'),
        AppRole.admin => find.text(adminHome),
      };
      testWidgets('${user.role.name} lands on their home and nowhere else', (
        tester,
      ) async {
        final repo = FakeAuthRepository(accounts: {..._users});
        await repo.signInWithPassword(email, 'password123');
        final container = await launch(tester, auth: repo);
        expect(home, findsOneWidget);

        final router = container.read(routerProvider);
        for (final other in AppRole.values.where((r) => r != user.role)) {
          router.go(other.homePath);
          await tester.pumpAndSettle();
          expect(find.text('No access'), findsOneWidget, reason: other.name);
          router.go('${other.homePath}/account');
          await tester.pumpAndSettle();
          expect(find.text('No access'), findsOneWidget, reason: other.name);
        }
      });
    }

    testWidgets('signing in from the customer app moves a rider home', (
      tester,
    ) async {
      final repo = FakeAuthRepository(accounts: {..._users});
      await launch(tester, auth: repo);
      expect(storeHome('customer'), findsOneWidget);
      await repo.signInWithPassword('rider@k.example', 'password123');
      await tester.pumpAndSettle();
      expect(find.text('Rider home'), findsOneWidget);
    });

    testWidgets('S-01 shows while the session loads; the link is kept', (
      tester,
    ) async {
      final repo = _SlowAuthRepository(accounts: {..._users});
      await repo.signInWithPassword('staff@k.example', 'password123');
      final container = await launch(tester, auth: repo, settle: false);
      await tester.pump();
      expect(find.byType(SplashPage), findsOneWidget);

      // A web reload of an admin page while the profile is still loading
      // must not bounce to No access as a "customer".
      container.read(routerProvider).go('/admin');
      await tester.pump();
      expect(find.byType(SplashPage), findsOneWidget);
      expect(find.text('No access'), findsNothing);

      repo.release();
      await tester.pumpAndSettle();
      expect(find.text(adminHome), findsOneWidget);
    });
  });
}
