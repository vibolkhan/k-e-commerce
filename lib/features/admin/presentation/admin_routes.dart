import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../catalog/presentation/catalog_list_page.dart';
import '../../catalog/presentation/import_wizard.dart';
import '../../catalog/presentation/product_editor_page.dart';
import '../../content/presentation/content_page.dart';
import '../../inventory/presentation/inventory_list_page.dart';
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
                section != AdminSection.catalog &&
                section != AdminSection.inventory &&
                section != AdminSection.content &&
                section != AdminSection.settings)
              GoRoute(
                path: section.segment,
                builder: (_, _) => AdminSectionPage(section: section),
              ),
          GoRoute(
            path: AdminSection.catalog.segment,
            builder: (_, _) => const CatalogListPage(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, _) => const ProductEditorPage(),
              ),
              GoRoute(
                path: 'import',
                builder: (_, _) => const ImportWizardPage(),
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) =>
                    ProductEditorPage(id: state.pathParameters['id']),
              ),
            ],
          ),
          GoRoute(
            path: AdminSection.inventory.segment,
            builder: (_, _) => const InventoryListPage(),
          ),
          GoRoute(
            path: AdminSection.content.segment,
            builder: (_, _) => const ContentAdminPage(),
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
