import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_role.dart';
import '../../../core/ui/k_ui.dart';
import '../../account/presentation/account_routes.dart';
import 'role_home_page.dart';

/// Customer and business shells: Home and Account tabs for now. Categories,
/// cart / quote list and orders join the bar as their tasks land.
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
            builder: (_, _) => RoleHomePage(role: role),
          ),
        ],
      ),
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
          KNavItem(icon: KIcons.account, label: l10n.navAccount),
        ],
      ),
    );
  }
}
