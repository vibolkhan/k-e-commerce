import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../domain/auth_intent.dart';
import 'complete_profile_page.dart';
import 'otp_page.dart';
import 'set_password_page.dart';
import 'sign_in_page.dart';

/// S-04 → S-05 → S-06 (`/sign-in`, `/sign-in/verify`, `/sign-in/profile`),
/// and the one-time password step for staff invited by email.
List<RouteBase> signInRoutes() => [
  GoRoute(
    path: AppRoutes.signIn,
    builder: (_, state) => SignInPage(
      intent: AuthIntent.tryParse(state.uri.queryParameters['intent']),
      from: state.uri.queryParameters['from'],
      blocked: state.uri.queryParameters['blocked'] == '1',
    ),
    routes: [
      GoRoute(
        path: 'verify',
        redirect: (_, state) => state.uri.queryParameters['phone'] == null
            ? AppRoutes.signIn
            : null,
        builder: (_, state) => OtpPage(
          phone: state.uri.queryParameters['phone']!,
          resendIn: state.extra is Duration
              ? state.extra! as Duration
              : const Duration(seconds: 60),
        ),
      ),
      GoRoute(path: 'profile', builder: (_, _) => const CompleteProfilePage()),
      GoRoute(path: 'set-password', builder: (_, _) => const SetPasswordPage()),
    ],
  ),
];
