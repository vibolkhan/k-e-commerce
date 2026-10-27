import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../notifications/presentation/inbox_page.dart';
import '../domain/admin_section.dart';
import 'admin_pages.dart';
import 'admin_shell.dart';
import 'staff_roles_page.dart';

/// `/admin/...`: every section inside [AdminShell]; the inbox and the
/// pending-invite page over it. Which sections a role may open is decided
/// by `adminRedirect` (app_router.dart).
List<RouteBase> adminRoutes({required GlobalKey<NavigatorState> rootKey}) => [
  ShellRoute(
    builder: (_, state, child) =>
        AdminShell(location: state.matchedLocation, child: child),
    routes: [
      GoRoute(
        path: AppRoutes.admin,
        builder: (_, _) =>
            const AdminSectionPage(section: AdminSection.dashboard),
        routes: [
          for (final section in AdminSection.values)
            if (section != AdminSection.dashboard &&
                section != AdminSection.settings)
              GoRoute(
                path: section.segment,
                builder: (_, _) => AdminSectionPage(section: section),
              ),
          GoRoute(
            path: AdminSection.settings.segment,
            builder: (_, _) => const AdminSettingsPage(),
            routes: [
              GoRoute(path: 'staff', builder: (_, _) => const StaffRolesPage()),
            ],
          ),
          GoRoute(path: 'more', builder: (_, _) => const AdminMorePage()),
        ],
      ),
    ],
  ),
  GoRoute(
    path: AppRoutes.adminPending,
    parentNavigatorKey: rootKey,
    builder: (_, _) => const AdminPendingPage(),
  ),
  GoRoute(
    path: AppRoutes.inbox(AppRoutes.admin),
    parentNavigatorKey: rootKey,
    builder: (_, _) => const InboxPage(shell: AppRoutes.admin),
  ),
];
