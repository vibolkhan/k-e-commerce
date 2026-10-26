import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/app.dart';
import 'package:k_e_commerce/core/config/app_config.dart';
import 'package:k_e_commerce/core/config/bootstrap.dart';
import 'package:k_e_commerce/core/router/app_role.dart';
import 'package:k_e_commerce/core/router/app_router.dart';
import 'package:k_e_commerce/core/router/app_routes.dart';
import 'package:k_e_commerce/features/auth/domain/auth_intent.dart';
import 'package:k_e_commerce/features/auth/domain/phone_number.dart';
import 'package:k_e_commerce/features/auth/domain/profile.dart';
import 'package:k_e_commerce/features/auth/presentation/auth_flow.dart';
import 'package:k_e_commerce/features/auth/presentation/auth_providers.dart';

import '../../helpers.dart';
import 'fake_auth_repository.dart';

void main() {
  group('KhPhone', () {
    test('normalises what people type to +855', () {
      expect(KhPhone.normalize('012 345 678'), '+85512345678');
      expect(KhPhone.normalize('12345678'), '+85512345678');
      expect(KhPhone.normalize('+855 12 345 678'), '+85512345678');
      expect(KhPhone.normalize('855-97-123-4567'), '+855971234567');
    });

    test('rejects what the server would reject', () {
      expect(KhPhone.normalize(''), isNull);
      expect(KhPhone.normalize('1234'), isNull);
      expect(KhPhone.normalize('+1 415 555 0100'), isNull);
      expect(KhPhone.normalize('12abc678'), isNull);
      expect(KhPhone.normalize('0012345678'), isNull);
    });

    test('displays in groups', () {
      expect(KhPhone.display('+85512345678'), '+855 12 345 678');
      expect(KhPhone.display('+855971234567'), '+855 97 123 4567');
    });

    test('emails are trimmed and lower-cased', () {
      expect(normalizeEmail(' Dara@KStore.example '), 'dara@kstore.example');
      expect(normalizeEmail('nope'), isNull);
    });
  });

  group('roles', () {
    test('database roles map to app shells; staff use admin', () {
      expect(appRoleFor('customer'), AppRole.customer);
      expect(appRoleFor('business'), AppRole.business);
      expect(appRoleFor('rider'), AppRole.rider);
      expect(appRoleFor('staff'), AppRole.admin);
      expect(appRoleFor(null), AppRole.customer);
      expect(appRoleFor('something-new'), AppRole.customer);
    });

    test('profiles without a name need S-06', () {
      final row = {
        'id': 'u1',
        'role': 'customer',
        'full_name': '  ',
        'is_blocked': false,
      };
      expect(Profile.fromRow(row).needsName, isTrue);
      expect(Profile.fromRow({...row, 'full_name': 'Dara'}).needsName, isFalse);
    });
  });

  group('return paths', () {
    test('only in-app paths outside the sign-in flow', () {
      expect(safeReturnPath('/customer/cart?step=2'), '/customer/cart?step=2');
      expect(safeReturnPath(null), isNull);
      expect(safeReturnPath('https://evil.example'), isNull);
      expect(safeReturnPath('//evil.example'), isNull);
      expect(safeReturnPath('/sign-in/verify'), isNull);
    });

    test('sign-in links carry intent, origin and the blocked flag', () {
      expect(AppRoutes.signInFor(), '/sign-in');
      final uri = Uri.parse(
        AppRoutes.signInFor(
          intent: AuthIntent.checkout.name,
          from: '/customer',
        ),
      );
      expect(uri.path, AppRoutes.signIn);
      expect(uri.queryParameters, {'intent': 'checkout', 'from': '/customer'});
      expect(AppRoutes.signInFor(blocked: true), '/sign-in?blocked=1');
      expect(AuthIntent.tryParse('rfq'), AuthIntent.rfq);
      expect(AuthIntent.tryParse('nope'), isNull);
    });
  });

  group('accountRedirect', () {
    const named = Profile(id: 'u', role: AppRole.customer, fullName: 'Dara');
    const nameless = Profile(id: 'u', role: AppRole.customer);
    const blocked = Profile(
      id: 'u',
      role: AppRole.customer,
      fullName: 'Vannak',
      isBlocked: true,
    );

    test('guests and complete accounts go where they asked', () {
      expect(accountRedirect(null, AppRoutes.customer), isNull);
      expect(accountRedirect(named, AppRoutes.customer), isNull);
    });

    test('blocked accounts are stopped at S-06b', () {
      expect(
        accountRedirect(blocked, AppRoutes.customer),
        AppRoutes.signInFor(blocked: true),
      );
    });

    test('accounts without a name finish S-06 first', () {
      expect(
        accountRedirect(nameless, '/customer/cart'),
        AppRoutes.signInProfile,
      );
    });

    test('the sign-in flow itself is never redirected', () {
      expect(accountRedirect(nameless, AppRoutes.signInProfile), isNull);
      expect(accountRedirect(blocked, AppRoutes.signIn), isNull);
    });
  });

  group('app', () {
    Future<void> pumpApp(WidgetTester tester, FakeAuthRepository repo) async {
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
          onboardedDevice,
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const KApp()),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a signed-in rider lands on the rider home', (tester) async {
      final repo = FakeAuthRepository(
        accounts: {
          'r@k.example': const Profile(
            id: 'r',
            role: AppRole.rider,
            fullName: 'Vuthy',
          ),
        },
      );
      await repo.signInWithPassword('r@k.example', 'password123');
      await pumpApp(tester, repo);
      expect(find.text('Rider home'), findsOneWidget);
      expect(find.text('Signed in as Vuthy'), findsOneWidget);
    });

    testWidgets('a session for a blocked account ends at S-06b', (
      tester,
    ) async {
      final repo = FakeAuthRepository(
        accounts: {
          'v@k.example': const Profile(
            id: 'v',
            role: AppRole.customer,
            fullName: 'Vannak',
          ),
        },
      );
      await repo.signInWithPassword('v@k.example', 'password123');
      // Blocked by sales after signing in.
      repo.accounts['v@k.example'] = const Profile(
        id: 'v',
        role: AppRole.customer,
        fullName: 'Vannak',
        isBlocked: true,
      );
      await pumpApp(tester, repo);
      expect(find.text('This account is unavailable'), findsOneWidget);
      expect(repo.signOuts, 1);
    });

    testWidgets('guests see Sign in on the Account tab', (tester) async {
      await pumpApp(tester, FakeAuthRepository());
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to K'), findsOneWidget);
    });
  });
}
