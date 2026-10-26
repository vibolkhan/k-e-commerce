import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/router/app_role.dart';
import 'package:k_e_commerce/core/router/app_routes.dart';
import 'package:k_e_commerce/core/ui/k_ui.dart';
import 'package:k_e_commerce/features/auth/domain/auth_outcome.dart';
import 'package:k_e_commerce/features/auth/domain/profile.dart';

import 'auth_harness.dart';
import 'fake_auth_repository.dart';

const phone = '+85512345678';

FakeAuthRepository dara() => FakeAuthRepository(
  accounts: {
    phone: const Profile(id: 'dara', role: AppRole.customer, fullName: 'Dara'),
  },
);

Finder get codeInput => find.descendant(
  of: find.byKey(const Key('otp-code')),
  matching: find.byType(TextField),
);

Future<void> enterCode(WidgetTester tester, String code) async {
  await tester.enterText(codeInput, code);
  await tester.pump();
}

Future<void> tapVerify(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('otp-verify')));
  await tester.pump();
  await tester.pump();
}

VoidCallback? verifyAction(WidgetTester tester) =>
    tester.widget<KButton>(find.byKey(const Key('otp-verify'))).onPressed;

/// Opens S-05 for [phone] on top of the origin page.
Future<void> openOtp(WidgetTester tester, FakeAuthRepository repo) async {
  final router = await pumpSignIn(tester, repo);
  unawaited(router.push(AppRoutes.signInVerifyFor(phone)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  group('S-05 verify code', () {
    testWidgets('shows the number and keeps Verify off until 6 digits', (
      tester,
    ) async {
      await openOtp(tester, dara());
      expect(find.text('Enter the 6-digit code'), findsOneWidget);
      expect(
        find.textContaining('+855 12 345 678', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Codes expire after 5 minutes.'), findsOneWidget);

      expect(verifyAction(tester), isNull);
      await enterCode(tester, '1234');
      expect(verifyAction(tester), isNull);
      await enterCode(tester, '123456');
      expect(verifyAction(tester), isNotNull);
    });

    testWidgets('a wrong code shows how many tries are left (S-05b)', (
      tester,
    ) async {
      await openOtp(tester, dara());
      await enterCode(tester, '000000');
      await tapVerify(tester);
      expect(find.text("That code isn't right. 4 tries left."), findsOneWidget);
      expect(tester.widget<KOtpField>(find.byType(KOtpField)).error, isTrue);

      // Typing again clears the error.
      await enterCode(tester, '00000');
      expect(find.textContaining("isn't right"), findsNothing);

      await enterCode(tester, '000000');
      await tapVerify(tester);
      expect(find.text("That code isn't right. 3 tries left."), findsOneWidget);
    });

    testWidgets('one try left reads in the singular', (tester) async {
      final repo = dara()..nextVerify = const WrongCredentials(1);
      await openOtp(tester, repo);
      await enterCode(tester, '000000');
      await tapVerify(tester);
      expect(find.text("That code isn't right. 1 try left."), findsOneWidget);
    });

    testWidgets('the 5th wrong code locks for 15 minutes (S-05c)', (
      tester,
    ) async {
      await openOtp(tester, dara());
      for (var i = 0; i < 5; i++) {
        await enterCode(tester, '00000$i');
        await tapVerify(tester);
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Too many attempts'), findsOneWidget);
      expect(
        find.text(
          'For your security, wait 15 minutes or sign in with email instead.',
        ),
        findsOneWidget,
      );
      expect(find.text('Use email'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Still on S-05, but nothing can be entered or sent until the lock ends.
      expect(find.text('Too many attempts'), findsNothing);
      expect(
        find.textContaining('Too many attempts. Try again after'),
        findsOneWidget,
      );
      expect(tester.widget<KOtpField>(find.byType(KOtpField)).enabled, isFalse);
      expect(verifyAction(tester), isNull);
      expect(find.textContaining('Resend code'), findsNothing);
    });

    testWidgets('even the right code is refused while locked', (tester) async {
      final repo = dara();
      await openOtp(tester, repo);
      for (var i = 0; i < 5; i++) {
        await repo.verifyOtp(phone, '000000');
      }
      await enterCode(tester, '123456');
      await tapVerify(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Too many attempts'), findsOneWidget);
      expect(repo.currentUserId, isNull);
    });

    testWidgets('"Use email" goes back to S-04 on the email tab', (
      tester,
    ) async {
      final repo = dara();
      final router = await pumpSignIn(tester, repo);
      unawaited(router.push(AppRoutes.signIn));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('sign-in-phone')),
        '012 345 678',
      );
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Enter the 6-digit code'), findsOneWidget);

      for (var i = 0; i < 5; i++) {
        await enterCode(tester, '00000$i');
        await tapVerify(tester);
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Use email'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Enter the 6-digit code'), findsNothing);
      expect(find.byKey(const Key('sign-in-email')), findsOneWidget);
      expect(find.byKey(const Key('sign-in-password')), findsOneWidget);
    });

    testWidgets('a locked number on resend shows the lock dialog', (
      tester,
    ) async {
      final repo = dara()
        ..nextSend = Locked(DateTime.now().add(const Duration(minutes: 15)));
      await openOtp(tester, repo);
      await tester.pump(const Duration(seconds: 61));
      await tester.tap(find.text('Resend code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Too many attempts'), findsOneWidget);
    });

    testWidgets('resend unlocks after 60 s and restarts the countdown', (
      tester,
    ) async {
      final repo = dara();
      await openOtp(tester, repo);

      expect(
        find.text('Resend code in 1:00', findRichText: true),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 18));
      expect(
        find.text('Resend code in 0:42', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Resend code'), findsNothing);

      await tester.pump(const Duration(seconds: 42));
      expect(find.text("Didn't get it?"), findsOneWidget);
      await tester.tap(find.text('Resend code'));
      await tester.pump();
      await tester.pump();

      expect(repo.sentTo, [phone]);
      expect(find.text('We sent a new code.'), findsOneWidget);
      expect(
        find.text('Resend code in 1:00', findRichText: true),
        findsOneWidget,
      );
      await settleToasts(tester);
    });

    testWidgets('a blocked account sees S-06b and leaves S-05', (tester) async {
      final repo = dara()..nextVerify = const Blocked();
      await openOtp(tester, repo);
      await enterCode(tester, '123456');
      await tapVerify(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('This account is unavailable'), findsOneWidget);
      expect(
        find.text('Please contact our support team to restore access.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the 6-digit code'), findsNothing);
      expect(find.text('Origin'), findsOneWidget);
    });

    testWidgets('the right code signs in', (tester) async {
      final repo = dara();
      await openOtp(tester, repo);
      await enterCode(tester, '123456');
      await tapVerify(tester);
      await tester.pumpAndSettle();
      expect(repo.currentUserId, 'dara');
      expect(find.text('Origin'), findsOneWidget);
    });
  });
}
