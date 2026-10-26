import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../domain/auth_intent.dart';
import 'auth_providers.dart';

/// Gate for protected actions (AUTH-03: checkout, RFQ, wishlist, reviews,
/// chat). Resolves true when the person is — or has just become — signed
/// in, so the caller simply carries on:
///
/// ```dart
/// if (!await requireSignIn(context, ref, AuthIntent.wishlist)) return;
/// await toggleWishlist(product);
/// ```
///
/// Sign-in is pushed on top of the current page, which stays mounted, so
/// its state (form input, scroll, the cart in providers) is kept. Resolves
/// false if they close sign-in.
Future<bool> requireSignIn(
  BuildContext context,
  WidgetRef ref,
  AuthIntent intent,
) async {
  if (ref.read(authRepositoryProvider).currentUserId != null) return true;
  final result = await context.push<bool>(
    AppRoutes.signInFor(
      intent: intent.name,
      from: GoRouterState.of(context).uri.toString(),
    ),
  );
  return result ?? false;
}
