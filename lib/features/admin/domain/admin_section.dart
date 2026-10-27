import '../../../core/router/app_routes.dart';
import 'staff_permissions.dart';

/// Sidebar groups (CmpAdminSidebar). Dashboard sits above them.
enum AdminGroup { sales, catalog, people, insights }

/// A back-office section: one sidebar entry, one route subtree under
/// `/admin`. Order is the sidebar's.
enum AdminSection {
  dashboard('', null, null, 'A-01'),
  orders('orders', AdminGroup.sales, PermissionArea.orders, 'A-02'),
  rfqs('rfqs', AdminGroup.sales, PermissionArea.rfqs, 'A-04'),
  returns('returns', AdminGroup.sales, PermissionArea.returns, 'A-09'),
  catalog('catalog', AdminGroup.catalog, PermissionArea.products, 'A-05'),
  inventory('inventory', AdminGroup.catalog, PermissionArea.products, 'A-06'),
  content('content', AdminGroup.catalog, PermissionArea.reviewsContent, 'A-12'),
  customers('customers', AdminGroup.people, PermissionArea.customers, 'A-07'),
  riders('riders', AdminGroup.people, PermissionArea.riders, 'A-08'),
  reviews('reviews', AdminGroup.people, PermissionArea.reviewsContent, 'A-10'),
  chat('chat', AdminGroup.people, PermissionArea.chat, 'A-11'),
  reports('reports', AdminGroup.insights, PermissionArea.reports, 'A-13'),
  settings('settings', AdminGroup.insights, PermissionArea.settings, 'A-14');

  const AdminSection(this.segment, this.group, this.area, this.screenId);

  /// Path segment under `/admin`; empty for the dashboard.
  final String segment;
  final AdminGroup? group;

  /// A-14d matrix row; null for the dashboard (everyone).
  final PermissionArea? area;

  /// Design screen id of the section's main page.
  final String screenId;

  String get path => AppRoutes.adminSection(segment);

  /// The section a back-office path belongs to; null outside `/admin` and
  /// for shell pages every staff member has (More, inbox, pending).
  static AdminSection? forPath(String path) {
    if (path == AppRoutes.admin || path == '${AppRoutes.admin}/') {
      return dashboard;
    }
    if (!path.startsWith('${AppRoutes.admin}/')) return null;
    final segment = path.substring(AppRoutes.admin.length + 1).split('/').first;
    for (final section in values) {
      if (section != dashboard && section.segment == segment) return section;
    }
    return null;
  }
}
