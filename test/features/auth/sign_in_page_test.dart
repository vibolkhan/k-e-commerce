import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/router/app_role.dart';
import 'package:k_e_commerce/core/router/app_routes.dart';
import 'package:k_e_commerce/features/auth/domain/auth_intent.dart';
import 'package:k_e_commerce/features/auth/domain/auth_outcome.dart';
import 'package:k_e_commerce/features/auth/domain/profile.dart';
import 'package:k_e_commerce/features/auth/presentation/require_sign_in.dart';

import 'auth_harness.dart';
import 'fake_auth_repository.dart';

const dara = Profile(id: 'dara', role: AppRole.customer, fullName: 'Dara Sok');
const vannak = Profile(
  id: 'vannak',
  role: AppRole.customer,
  fullName: 'Vannak Sum',
  isBlocked: true,
);

FakeAuthRepository repo() => FakeAuthRepository(
  accounts: {
    '+85512345678': dara,
    'dara@kstore.example': dara,
    '+85512345680': vannak,
  },
);

Future<void> openSignIn(WidgetTester tester, FakeAuthRepository repo) async {
  final router = await pumpSignIn(tester, repo);
  unawaited(router.push(AppRoutes.signIn));
  await tester.pumpAndSettle();
}

Future<void> useEmailTab(WidgetTester tester) async {
  await tester.tap(find.text('Email').first);
  await tester.pumpAndSettle();
}

Future<void> signInWithEmail(
  WidgetTester tester,
  String email,
  String password,
) async {
  await tester.enterText(find.byKey(const Key('sign-in-email')), email);
  await tester.enterText(find.byKey(const Key('sign-in-password')), password);
  await tester.tap(find.widgetWithText(InkWell, 'Sign in').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// A page with its own state and a protected action (wishlist).
class _ProductPage extends ConsumerStatefulWidget {
  const _ProductPage();

  @override
  ConsumerState<_ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends ConsumerState<_ProductPage> {
  var qty = 1;
  var wished = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text('Qty $qty'),
        TextButton(
          onPressed: () => setState(() => qty++),
          child: const Text('More'),
        ),
        TextButton(
          onPressed: () async {
            if (!await requireSignIn(context, ref, AuthIntent.wishlist)) return;
            setState(() => wished = true);
          },
          child: const Text('Save to wishlist'),
        ),
        Text(wished ? 'Saved' : 'Not saved'),
      ],
    ),
  );
}

void main() {
  group('S-04 phone', () {
    testWidgets('phone is the default with +855 and both social buttons', (
      tester,
    ) async {
      await openSignIn(tester, repo());
      expect(find.text('Sign in to K'), findsOneWidget);
      expect(find.text('+855'), findsOneWidget);
      expect(find.text("We'll text you a 6-digit code."), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with Apple'), findsOneWidget);
    });

    testWidgets('rejects a number that is not Cambodian mobile', (
      tester,
    ) async {
      final fake = repo();
      await openSignIn(tester, fake);
      await tester.enterText(find.byKey(const Key('sign-in-phone')), '1234');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a Cambodian mobile number, like 12 345 678.'),
        findsOneWidget,
      );
      expect(fake.sentTo, isEmpty);
    });

    testWidgets('sends a code and opens S-05', (tester) async {
      final fake = repo();
      await openSignIn(tester, fake);
      await tester.enterText(
        find.byKey(const Key('sign-in-phone')),
        '012 345 678',
      );
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(fake.sentTo, ['+85512345678']);
      expect(find.text('Enter the 6-digit code'), findsOneWidget);
    });

    testWidgets('a locked number shows S-05c before any code is sent', (
      tester,
    ) async {
      final fake = repo()
        ..nextSend = Locked(DateTime.now().add(const Duration(minutes: 15)));
      await openSignIn(tester, fake);
      await tester.enterText(
        find.byKey(const Key('sign-in-phone')),
        '12345678',
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Too many attempts'), findsOneWidget);
      await tester.tap(find.text('Use email'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sign-in-password')), findsOneWidget);
    });

    testWidgets('a blocked number sees S-06b; Contact support answers', (
      tester,
    ) async {
      await openSignIn(tester, repo());
      await tester.enterText(
        find.byKey(const Key('sign-in-phone')),
        '12345680',
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('This account is unavailable'), findsOneWidget);
      expect(find.text('Enter the 6-digit code'), findsNothing);

      await tester.tap(find.text('Contact support'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Support chat'), findsOneWidget);
      await settleToasts(tester);
    });

    testWidgets('a send failure is explained under the field', (tester) async {
      final fake = repo()..nextSend = const SendFailed();
      await openSignIn(tester, fake);
      await tester.enterText(
        find.byKey(const Key('sign-in-phone')),
        '12345678',
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        find.text("We couldn't send the code. Check the number and try again."),
        findsOneWidget,
      );
    });
  });

  group('S-04b email', () {
    testWidgets('a wrong password shows tries left', (tester) async {
      await openSignIn(tester, repo());
      await useEmailTab(tester);
      await signInWithEmail(tester, 'dara@kstore.example', 'nope');
      expect(
        find.text('Incorrect email or password. 4 tries left.'),
        findsOneWidget,
      );
    });

    testWidgets('5 wrong passwords lock and offer phone instead', (
      tester,
    ) async {
      await openSignIn(tester, repo());
      await useEmailTab(tester);
      for (var i = 0; i < 5; i++) {
        await signInWithEmail(tester, 'dara@kstore.example', 'nope$i');
      }
      await tester.pumpAndSettle();
      expect(find.text('Too many attempts'), findsOneWidget);
      expect(
        find.text(
          'For your security, wait 15 minutes or sign in with your phone instead.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Use phone'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sign-in-phone')), findsOneWidget);
    });

    testWidgets('validates email and password before calling the server', (
      tester,
    ) async {
      await openSignIn(tester, repo());
      await useEmailTab(tester);
      await signInWithEmail(tester, 'not-an-email', '');
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
    });

    testWidgets('the right password returns to the page underneath', (
      tester,
    ) async {
      final fake = repo();
      await openSignIn(tester, fake);
      await useEmailTab(tester);
      await signInWithEmail(tester, 'Dara@KStore.example', 'password123');
      await tester.pumpAndSettle();
      expect(fake.currentUserId, 'dara');
      expect(find.text('Origin'), findsOneWidget);
    });

    testWidgets('forgot password sends the reset email', (tester) async {
      final fake = repo();
      await openSignIn(tester, fake);
      await useEmailTab(tester);
      await tester.enterText(
        find.byKey(const Key('sign-in-email')),
        'dara@kstore.example',
      );
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(find.text('Reset your password'), findsOneWidget);
      await tester.tap(find.text('Send link'));
      await tester.pumpAndSettle();
      expect(fake.resetEmails, ['dara@kstore.example']);
      expect(find.text('Check your inbox for the reset link.'), findsOneWidget);
    });

    testWidgets('create account → S-06 → back where they started', (
      tester,
    ) async {
      final fake = repo();
      await openSignIn(tester, fake);
      await useEmailTab(tester);
      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('sign-in-email')),
        'srey@example.com',
      );
      await tester.enterText(find.byKey(const Key('sign-in-password')), '123');
      await tester.tap(find.widgetWithText(InkWell, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Use at least 6 characters.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('sign-in-password')),
        'secret123',
      );
      await tester.tap(find.widgetWithText(InkWell, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('What should we call you?'), findsOneWidget);
    });
  });

  group('S-06 complete profile', () {
    testWidgets('a name is required, then the flow finishes', (tester) async {
      final fake = repo();
      final router = await pumpSignIn(tester, fake);
      unawaited(router.push(AppRoutes.signIn));
      await tester.pumpAndSettle();
      // New phone number → new account with no name.
      await tester.enterText(
        find.byKey(const Key('sign-in-phone')),
        '15999888',
      );
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('otp-code')),
          matching: find.byType(TextField),
        ),
        '123456',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('otp-verify')));
      await tester.pumpAndSettle();

      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.text('Almost done'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-continue')));
      await tester.pumpAndSettle();
      expect(find.text('Enter your name.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('profile-email')),
        'bad-email',
      );
      await tester.enterText(
        find.byKey(const Key('profile-name')),
        'Srey Neang',
      );
      await tester.tap(find.byKey(const Key('profile-continue')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('profile-email')),
        'srey@example.com',
      );
      await tester.tap(find.byKey(const Key('profile-continue')));
      await tester.pumpAndSettle();
      expect(fake.completed?.fullName, 'Srey Neang');
      expect(fake.completed?.email, 'srey@example.com');
      expect(fake.completed?.emailReceipts, isTrue);
      expect(find.text('Origin'), findsOneWidget);
    });
  });

  group('S-06b blocked and social', () {
    testWidgets('arriving with blocked=1 signs out and shows S-06b', (
      tester,
    ) async {
      final fake = repo();
      await pumpSignIn(
        tester,
        fake,
        initialLocation: AppRoutes.signInFor(blocked: true),
      );
      expect(find.text('This account is unavailable'), findsOneWidget);
      expect(fake.signOuts, 1);
    });

    testWidgets('a blocked Google account cannot continue', (tester) async {
      final fake = repo()..nextSocial = const Blocked();
      await openSignIn(tester, fake);
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.text('This account is unavailable'), findsOneWidget);
    });

    testWidgets('Apple sign-in returns to the page underneath', (tester) async {
      final fake = repo()
        ..accounts['apple'] = const Profile(
          id: 'apple-user',
          role: AppRole.customer,
          fullName: 'Lina',
        );
      await openSignIn(tester, fake);
      await tester.tap(find.text('Continue with Apple'));
      await tester.pumpAndSettle();
      expect(fake.currentUserId, 'apple-user');
      expect(find.text('Origin'), findsOneWidget);
    });

    testWidgets('closing Google sign-in is not an error', (tester) async {
      final fake = repo()..nextSocial = const Cancelled();
      await openSignIn(tester, fake);
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to K'), findsOneWidget);
      expect(find.textContaining("didn't finish"), findsNothing);
    });
  });

  group('return to intended action', () {
    testWidgets('wishlist → sign in → back with state kept, action done', (
      tester,
    ) async {
      final fake = repo();
      await pumpSignIn(tester, fake, origin: const _ProductPage());
      await tester.tap(find.text('More'));
      await tester.tap(find.text('More'));
      await tester.pump();
      expect(find.text('Qty 3'), findsOneWidget);

      await tester.tap(find.text('Save to wishlist'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to K'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('sign-in-phone')),
        '12345678',
      );
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('otp-code')),
          matching: find.byType(TextField),
        ),
        '123456',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('otp-verify')));
      await tester.pumpAndSettle();

      expect(find.text('Qty 3'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('closing sign-in leaves the action undone', (tester) async {
      await pumpSignIn(tester, repo(), origin: const _ProductPage());
      await tester.tap(find.text('Save to wishlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Not saved'), findsOneWidget);
    });

    testWidgets('signed-in people go straight through', (tester) async {
      final fake = repo();
      await fake.signInWithPassword('dara@kstore.example', 'password123');
      await pumpSignIn(tester, fake, origin: const _ProductPage());
      await tester.tap(find.text('Save to wishlist'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to K'), findsNothing);
      expect(find.text('Saved'), findsOneWidget);
    });
  });
}
