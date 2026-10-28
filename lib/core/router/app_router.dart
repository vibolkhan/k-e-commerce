import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/domain/admin_section.dart';
import '../../features/admin/domain/staff_permissions.dart';
import '../../features/admin/domain/staff_role.dart';
import '../../features/admin/presentation/admin_providers.dart';
import '../../features/admin/presentation/admin_routes.dart';
import '../../features/auth/domain/profile.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/auth_routes.dart';
import '../../features/design_gallery/presentation/design_gallery_page.dart';
import '../../features/onboarding/data/onboarding_store.dart';
import '../../features/onboarding/presentation/intro_page.dart';
import '../../features/onboarding/presentation/language_step_page.dart';
import '../../features/onboarding/presentation/splash_page.dart';
import '../../features/shell/presentation/role_home_page.dart';
import '../../features/shell/presentation/shopper_shell.dart';
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
/// S-06 first; staff invited by email set a password first. The sign-in flow
/// itself is never redirected. Pure for tests.
String? accountRedirect(Profile? profile, String path) {
  if (profile == null || AppRoutes.isSignInFlow(path)) return null;
  if (profile.isBlocked) return AppRoutes.signInFor(blocked: true);
  if (profile.needsName) return AppRoutes.signInProfile;
  if (profile.needsPassword) return AppRoutes.signInSetPassword;
  return null;
}

/// Redirect rule inside the back office (F08): a staff member without an
/// active membership ([staffRole] null) only gets the pending page; a
/// section the role may not open is "No access", like another role's
/// shell. The server refuses the same data either way. Pure for tests.
String? adminRedirect(StaffRole? staffRole, String path) {
  final inAdmin =
      path == AppRoutes.admin || path.startsWith('${AppRoutes.admin}/');
  if (!inAdmin) return null;
  if (staffRole == null) {
    return path == AppRoutes.adminPending ? null : AppRoutes.adminPending;
  }
  if (path == AppRoutes.adminPending) return AppRoutes.admin;
  final section = AdminSection.forPath(path);
  if (section != null && !canOpen(staffRole, section)) {
    return AppRoutes.forbidden;
  }
  // Read-only roles can browse the catalogue but not create or import.
  if ((path == AppRoutes.adminProductNew ||
          path == AppRoutes.adminCatalogImport) &&
      !canEdit(staffRole, PermissionArea.products)) {
    return AppRoutes.adminCatalog;
  }
  return null;
}

/// Where App Flow F0 stands on this device.
class LaunchState {
  const LaunchState({
    required this.sessionReady,
    required this.languageChosen,
    required this.introSeen,
    required this.role,
  });

  /// The saved session (and its profile) has loaded.
  final bool sessionReady;
  final bool languageChosen;
  final bool introSeen;
  final AppRole role;
}

/// Redirect rule for launch (F0): S-01 until the session and profile have
/// loaded, then S-02 and S-03 on first launch, then the role's home — or
/// the in-app link that opened the app, carried along as `from`. Riders and
/// staff skip the shopping intro. Sign-in is never held back. Pure for tests.
String? launchRedirect(LaunchState state, Uri uri) {
  final path = uri.path;
  if (AppRoutes.isSignInFlow(path)) return null;
  final inLaunch = AppRoutes.isLaunch(path);
  final link = inLaunch ? uri.queryParameters['from'] : uri.toString();
  final from = link != null && link.startsWith('/') && !link.startsWith('//')
      ? link
      : null;
  String? step(String target) =>
      path == target ? null : AppRoutes.launchStep(target, from: from);

  if (!state.sessionReady) return step(AppRoutes.splash);
  if (!state.languageChosen) return step(AppRoutes.welcomeLanguage);
  final shopper =
      state.role == AppRole.customer || state.role == AppRole.business;
  if (shopper && !state.introSeen) return step(AppRoutes.welcomeIntro);
  if (inLaunch) return from ?? state.role.homePath;
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final config = ref.watch(appConfigProvider);
  final rootKey = GlobalKey<NavigatorState>();
  // Re-run redirects when the account, role or launch progress changes
  // (session restored, sign-in, block, S-06, onboarding steps).
  final refresh = ValueNotifier(0);
  void bump(Object? _, Object? _) => refresh.value++;
  ref.listen(currentProfileProvider, bump);
  ref.listen(currentRoleProvider, bump);
  ref.listen<StaffRole?>(currentStaffRoleProvider, bump);
  ref.listen(onboardingProgressProvider, bump);

  LaunchState launchState() {
    final profile = ref.read(currentProfileProvider);
    final done = ref.read(onboardingProgressProvider);
    return LaunchState(
      sessionReady: profile.hasValue || profile.hasError,
      languageChosen: done.contains(OnboardingStep.language),
      introSeen: done.contains(OnboardingStep.intro),
      role: ref.read(currentRoleProvider),
    );
  }

  bool isSignedIn() => ref.read(currentProfileProvider).value != null;

  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: AppRoutes.root,
    refreshListenable: refresh,
    redirect: (context, state) =>
        launchRedirect(launchState(), state.uri) ??
        accountRedirect(
          ref.read(currentProfileProvider).value,
          state.matchedLocation,
        ) ??
        roleRedirect(ref.read(currentRoleProvider), state.matchedLocation) ??
        adminRedirect(
          ref.read(currentStaffRoleProvider),
          state.matchedLocation,
        ),
    errorBuilder: (context, state) => const ErrorPage.notFound(),
    routes: [
      GoRoute(path: AppRoutes.root, redirect: (_, _) => null),
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashPage()),
      GoRoute(
        path: AppRoutes.welcomeLanguage,
        builder: (_, _) => const LanguageStepPage(),
      ),
      GoRoute(
        path: AppRoutes.welcomeIntro,
        builder: (_, _) => const IntroPage(),
      ),
      GoRoute(path: AppRoutes.loading, builder: (_, _) => const LoadingPage()),
      GoRoute(
        path: AppRoutes.forbidden,
        builder: (_, _) => const ErrorPage.forbidden(),
      ),
      ...signInRoutes(),
      for (final role in [AppRole.customer, AppRole.business])
        shopperShell(role, rootKey: rootKey, isSignedIn: isSignedIn),
      GoRoute(
        path: AppRole.rider.homePath,
        builder: (_, _) => const RoleHomePage(role: AppRole.rider),
      ),
      ...adminRoutes(rootKey: rootKey),
      if (!config.isProd)
        GoRoute(
          path: AppRoutes.designGallery,
          builder: (_, _) => const DesignGalleryPage(),
        ),
    ],
  );
  // A role change (sign-in, sign-out, debug switcher) opens the new role's
  // home unless they are already inside it. During launch the redirect
  // decides, so a deep link survives the profile loading.
  ref.listen(currentRoleProvider, (_, role) {
    final path = router.routerDelegate.currentConfiguration.uri.path;
    final inOwnShell =
        path == role.homePath || path.startsWith('${role.homePath}/');
    if (!AppRoutes.isLaunch(path) && !inOwnShell) router.go(role.homePath);
  });
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
