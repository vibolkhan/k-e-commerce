import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/app.dart';
import 'package:k_e_commerce/core/config/app_config.dart';
import 'package:k_e_commerce/core/config/bootstrap.dart';
import 'package:k_e_commerce/core/router/app_role.dart';
import 'package:k_e_commerce/core/router/app_router.dart';
import 'package:k_e_commerce/core/router/app_routes.dart';
import 'package:k_e_commerce/core/ui/k_ui.dart';
import 'package:k_e_commerce/features/account/data/account_repository.dart';
import 'package:k_e_commerce/features/account/domain/delete_account_outcome.dart';
import 'package:k_e_commerce/features/account/presentation/account_page.dart';
import 'package:k_e_commerce/features/auth/domain/profile.dart';
import 'package:k_e_commerce/features/auth/presentation/auth_providers.dart';

import '../../helpers.dart';
import '../auth/auth_harness.dart';
import '../auth/fake_auth_repository.dart';
import 'fake_account_repository.dart';

const _dara = Profile(
  id: 'c',
  role: AppRole.customer,
  fullName: 'Dara Sok',
  email: 'dara@example.com',
  phone: '+85512345678',
);
const _sokha = Profile(
  id: 'b',
  role: AppRole.business,
  fullName: 'Sokha Chan',
  phone: '+85512345681',
);

/// Scrolls the Account list until [finder] is built and fully on screen.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find
        .descendant(
          of: find.byType(AccountPage),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  late FakeAuthRepository auth;
  late FakeAccountRepository account;

  /// The whole app, already onboarded, signed in as [email] (or a guest),
  /// opened on the Account tab.
  Future<ProviderContainer> openAccount(
    WidgetTester tester, {
    String? email = 'dara@k.example',
  }) async {
    setViewSize(tester, const Size(390, 844));
    auth = FakeAuthRepository(
      accounts: {'dara@k.example': _dara, 'sokha@k.example': _sokha},
    );
    addTearDown(auth.dispose);
    account = FakeAccountRepository(auth);
    if (email != null) await auth.signInWithPassword(email, 'password123');
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            env: AppEnv.dev,
            supabaseUrl: '',
            supabaseAnonKey: '',
          ),
        ),
        authRepositoryProvider.overrideWithValue(auth),
        accountRepositoryProvider.overrideWithValue(account),
        onboardedDevice,
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const KApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    return container;
  }

  group('S-08a guest', () {
    testWidgets('prompts to sign in and keeps app settings', (tester) async {
      await openAccount(tester, email: null);
      expect(find.text('Sign in for faster checkout'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
      expect(find.text('Delete account'), findsNothing);

      await tester.tap(find.byKey(const Key('account-sign-in')));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to K'), findsOneWidget);
    });

    testWidgets('edit and delete links bounce a guest to Account', (
      tester,
    ) async {
      final container = await openAccount(tester, email: null);
      container
          .read(routerProvider)
          .go(AppRoutes.accountDelete(AppRoutes.customer));
      await tester.pumpAndSettle();
      expect(find.text('Sign in for faster checkout'), findsOneWidget);
    });
  });

  group('S-08 signed in', () {
    testWidgets('shows the profile, activity and settings', (tester) async {
      await openAccount(tester);
      expect(find.text('Dara Sok'), findsOneWidget);
      expect(find.text('+855 12 345 678'), findsOneWidget);
      expect(find.text('DS'), findsOneWidget);
      expect(find.text('Become a business buyer'), findsOneWidget);
      for (final row in ['Orders', 'Wishlist', 'Returns', 'Addresses']) {
        expect(find.text(row), findsWidgets);
      }
      await reveal(tester, find.byKey(const Key('account-delete')));
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('business buyers have no upgrade prompt', (tester) async {
      await openAccount(tester, email: 'sokha@k.example');
      expect(find.text('Sokha Chan'), findsOneWidget);
      expect(find.text('Become a business buyer'), findsNothing);
    });

    testWidgets('rows for later features say so', (tester) async {
      await openAccount(tester);
      await tester.tap(find.text('Wishlist'));
      await tester.pump();
      expect(find.text('Coming in a later update.'), findsOneWidget);
      await settleToasts(tester);
    });

    testWidgets('Language opens S-08c', (tester) async {
      await openAccount(tester);
      await tester.tap(find.byKey(const Key('account-language')));
      await tester.pumpAndSettle();
      expect(find.text('Current language'), findsOneWidget);
    });
  });

  group('S-08b edit profile', () {
    testWidgets('validates, saves and shows the new name', (tester) async {
      await openAccount(tester);
      await tester.tap(find.byKey(const Key('account-edit')));
      await tester.pumpAndSettle();
      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('+855 12 345 678'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('edit-name')), '  ');
      await tester.enterText(find.byKey(const Key('edit-email')), 'nope');
      await tester.tap(find.byKey(const Key('edit-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter your name.'), findsOneWidget);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(account.updates, 0);

      await tester.enterText(find.byKey(const Key('edit-name')), 'Dara S.');
      await tester.enterText(find.byKey(const Key('edit-email')), '');
      await tester.tap(find.byKey(const Key('edit-save')));
      await tester.pumpAndSettle();
      expect(account.updates, 1);
      expect(auth.accounts['dara@k.example']!.email, isNull);
      expect(find.text('Dara S.'), findsOneWidget); // back on S-08
      await settleToasts(tester);
    });
  });

  group('S-08e sign out', () {
    testWidgets('asks first; Cancel keeps the session', (tester) async {
      await openAccount(tester);
      await reveal(tester, find.byKey(const Key('account-sign-out')));
      await tester.tap(find.byKey(const Key('account-sign-out')));
      await tester.pumpAndSettle();
      expect(find.text('Sign out?'), findsOneWidget);
      expect(
        find.text('Your cart stays saved on this device.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(auth.signOuts, 0);

      await tester.tap(find.byKey(const Key('account-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(KButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(auth.signOuts, 1);
      expect(find.text('Sign in for faster checkout'), findsOneWidget);
    });
  });

  group('S-08f/g delete account', () {
    Future<void> openDelete(WidgetTester tester) async {
      await reveal(tester, find.byKey(const Key('account-delete')));
      await tester.tap(find.byKey(const Key('account-delete')));
      await tester.pumpAndSettle();
    }

    KButton submit(WidgetTester tester) =>
        tester.widget<KButton>(find.byKey(const Key('delete-submit')));

    testWidgets('needs the tick, confirms, then signs out to guest home', (
      tester,
    ) async {
      await openAccount(tester);
      await openDelete(tester);
      expect(find.text('What will be deleted'), findsOneWidget);
      expect(
        find.text('Invoices and order records we\'re required by law to keep'),
        findsOneWidget,
      );
      expect(submit(tester).onPressed, isNull);

      await tester.tap(find.byKey(const Key('delete-reason')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I don\'t use the app any more'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-understand')));
      await tester.pump();
      expect(submit(tester).onPressed, isNotNull);

      // S-08g: Keep account changes nothing.
      await tester.tap(find.byKey(const Key('delete-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Delete your account?'), findsOneWidget);
      await tester.tap(find.text('Keep account'));
      await tester.pumpAndSettle();
      expect(account.deleteReasons, isEmpty);

      await tester.tap(find.byKey(const Key('delete-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(KButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(account.deleteReasons, ['not_using']);
      expect(auth.signOuts, 1);
      expect(auth.currentUserId, isNull);
      expect(find.text('Customer home'), findsOneWidget);
      expect(find.text('Your account has been deleted.'), findsOneWidget);
      await settleToasts(tester);
    });

    testWidgets('an order in progress keeps the account', (tester) async {
      await openAccount(tester);
      account.nextDelete = const HasActiveOrders();
      await openDelete(tester);
      await tester.tap(find.byKey(const Key('delete-understand')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('delete-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(KButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete-refusal')), findsOneWidget);
      expect(find.textContaining('orders or returns in progress'), findsOne);
      expect(account.deleteReasons, [null]);
      expect(auth.signOuts, 0);
      expect(find.text('What will be deleted'), findsOneWidget);
    });
  });
}
