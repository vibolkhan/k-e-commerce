import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/shell/presentation/role_home_page.dart';
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

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.root,
    redirect: (context, state) =>
        roleRedirect(ref.read(currentRoleProvider), state.matchedLocation),
    errorBuilder: (context, state) => const ErrorPage.notFound(),
    routes: [
      GoRoute(path: AppRoutes.root, redirect: (_, _) => null),
      GoRoute(path: AppRoutes.loading, builder: (_, _) => const LoadingPage()),
      GoRoute(
        path: AppRoutes.forbidden,
        builder: (_, _) => const ErrorPage.forbidden(),
      ),
      for (final role in AppRole.values)
        GoRoute(
          path: role.homePath,
          builder: (_, _) => RoleHomePage(role: role),
        ),
    ],
  );
  // Re-run redirects when the role changes.
  ref.listen(currentRoleProvider, (_, role) => router.go(role.homePath));
  ref.onDispose(router.dispose);
  return router;
});
