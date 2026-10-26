import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/profile.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/auth_routes.dart';
import '../../features/design_gallery/presentation/design_gallery_page.dart';
import '../../features/shell/presentation/role_home_page.dart';
import '../config/bootstrap.dart';
import '../ui/pages/error_page.dart';
import '../ui/pages/loading_page.dart';
import 'app_role.dart';
import 'app_routes.dart';

/// Redirect rule: `/` goes to the role's home, and a role can only open its
/// own shell. Kept pure so it can be unit-tested.
String? roleRedirect(AppRole role, String path) {
  if (path == AppRoutes.root) return role.homePath;
  for (final other in AppRole.values) {
    final inShell =
        path == other.homePath || path.startsWith('${other.homePath}/');
    if (inShell && other != role) return AppRoutes.forbidden;
  }
  return null;
}

/// Redirect rule for the signed-in account: a blocked account lands on S-04
/// with S-06b (and is signed out there); an account without a name finishes
/// S-06 first. The sign-in flow itself is never redirected. Pure for tests.
String? accountRedirect(Profile? profile, String path) {
  if (profile == null || AppRoutes.isSignInFlow(path)) return null;
  if (profile.isBlocked) return AppRoutes.signInFor(blocked: true);
  if (profile.needsName) return AppRoutes.signInProfile;
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final config = ref.watch(appConfigProvider);
  // Re-run redirects when the account changes (sign-in, block, S-06).
  final accountChanged = ValueNotifier(0);
  ref.listen(currentProfileProvider, (_, _) => accountChanged.value++);
  final router = GoRouter(
    initialLocation: AppRoutes.root,
    refreshListenable: accountChanged,
    redirect: (context, state) =>
        accountRedirect(
          ref.read(currentProfileProvider).value,
          state.matchedLocation,
        ) ??
        roleRedirect(ref.read(currentRoleProvider), state.matchedLocation),
    errorBuilder: (context, state) => const ErrorPage.notFound(),
    routes: [
      GoRoute(path: AppRoutes.root, redirect: (_, _) => null),
      GoRoute(path: AppRoutes.loading, builder: (_, _) => const LoadingPage()),
      GoRoute(
        path: AppRoutes.forbidden,
        builder: (_, _) => const ErrorPage.forbidden(),
      ),
      ...signInRoutes(),
      for (final role in AppRole.values)
        GoRoute(
          path: role.homePath,
          builder: (_, _) => RoleHomePage(role: role),
        ),
      if (!config.isProd)
        GoRoute(
          path: AppRoutes.designGallery,
          builder: (_, _) => const DesignGalleryPage(),
        ),
    ],
  );
  // Re-run redirects when the role changes.
  ref.listen(currentRoleProvider, (_, role) => router.go(role.homePath));
  ref.onDispose(() {
    router.dispose();
    accountChanged.dispose();
  });
  return router;
});
