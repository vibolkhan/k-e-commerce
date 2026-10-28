import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_role.dart';
import '../../../core/ui/k_ui.dart';
import '../../account/presentation/account_routes.dart';
import '../../notifications/presentation/notifications_routes.dart';
import '../../storefront/presentation/home_page.dart';
import '../../storefront/presentation/storefront_routes.dart';

/// Customer and business shells: Home, Categories and Account tabs for now.
/// Cart / quote list and orders join the bar as their tasks land.
StatefulShellRoute shopperShell(
  AppRole role, {
  required GlobalKey<NavigatorState> rootKey,
  required bool Function() isSignedIn,
}) {
  return StatefulShellRoute.indexedStack(
    builder: (_, _, shell) => ShopperShell(shell: shell),
    branches: [
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: role.homePath,
            builder: (_, _) => HomePage(role: role),
            routes: [
              ...notificationRoutes(
                role,
                rootKey: rootKey,
                isSignedIn: isSignedIn,
              ),
              ...homeBrowseRoutes(role, rootKey: rootKey),
            ],
          ),
        ],
      ),
      StatefulShellBranch(routes: [categoriesRoute(role)]),
      StatefulShellBranch(
        routes: [accountRoute(role, rootKey: rootKey, isSignedIn: isSignedIn)],
      ),
    ],
  );
}

class ShopperShell extends StatelessWidget {
  const ShopperShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: KBottomNav(
        currentIndex: shell.currentIndex,
        // Tapping the open tab returns it to its first page.
        onTap: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        items: [
          KNavItem(icon: KIcons.home, label: l10n.navHome),
          KNavItem(icon: KIcons.categories, label: l10n.navCategories),
          KNavItem(icon: KIcons.account, label: l10n.navAccount),
        ],
      ),
    );
  }
}
