import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_role.dart';
import '../../../core/router/app_routes.dart';
import 'account_page.dart';
import 'delete_account_page.dart';
import 'edit_profile_page.dart';

/// `<shell>/account` (S-08 / S-08a) with S-08b and S-08f on the root
/// navigator, over the bottom navigation. Guests asking for edit or delete
/// land on the account tab instead.
GoRoute accountRoute(
  AppRole role, {
  required GlobalKey<NavigatorState> rootKey,
  required bool Function() isSignedIn,
}) {
  final account = AppRoutes.account(role.homePath);
  String? signedInOnly(BuildContext _, GoRouterState _) =>
      isSignedIn() ? null : account;
  return GoRoute(
    path: account,
    builder: (_, _) => AccountPage(role: role),
    routes: [
      GoRoute(
        path: 'edit',
        parentNavigatorKey: rootKey,
        redirect: signedInOnly,
        builder: (_, _) => const EditProfilePage(),
      ),
      GoRoute(
        path: 'delete',
        parentNavigatorKey: rootKey,
        redirect: signedInOnly,
        builder: (_, _) => const DeleteAccountPage(),
      ),
    ],
  );
}
