import 'admin_section.dart';
import 'staff_role.dart';

/// How much of an area a role gets (A-14d "Roles & permissions").
enum AccessLevel { full, view, partial, none }

/// What the partial cells on A-14d say.
enum AccessDetail { reviews, content, salesAndRfq, stock }

class AreaAccess {
  const AreaAccess(this.level, [this.detail]);

  static const full = AreaAccess(AccessLevel.full);
  static const view = AreaAccess(AccessLevel.view);
  static const none = AreaAccess(AccessLevel.none);

  final AccessLevel level;
  final AccessDetail? detail;
}

/// The rows of the A-14d matrix, in its order.
enum PermissionArea {
  orders,
  rfqs,
  returns,
  products,
  customers,
  riders,
  reviewsContent,
  chat,
  reports,
  settings,
}

/// A-14d, the single client-side copy of who may open what. The menu and the
/// router read it; RLS and the Edge Functions enforce the same split on the
/// server (supabase/tests/database/06_staff, 12_staff_admin).
const Map<PermissionArea, Map<StaffRole, AreaAccess>> staffMatrix = {
  PermissionArea.orders: {
    StaffRole.superAdmin: AreaAccess.full,
    StaffRole.sales: AreaAccess.full,
    StaffRole.support: AreaAccess.view,
    StaffRole.catalog: AreaAccess.none,
  },
  PermissionArea.rfqs: {
    StaffRole.superAdmin: AreaAccess.full,
    StaffRole.sales: AreaAccess.full,
    StaffRole.support: AreaAccess.none,
    StaffRole.catalog: AreaAccess.none,
  },
  PermissionArea.returns: {
    StaffRole.superAdmin: AreaAccess.full,
    StaffRole.sales: AreaAccess.none,
    StaffRole.support: AreaAccess.full,
    StaffRole.catalog: AreaAccess.none,
  },
  PermissionArea.products: {
    StaffRole.superAdmin: AreaAccess.full,
    StaffRole.sales: AreaAccess.view,
    StaffRole.support: AreaAccess.view,
    StaffRole.catalog: AreaAccess.full,
  },
  PermissionArea.customers: {
    StaffRole.superAdmin: AreaAccess.full,
    StaffRole.sales: AreaAccess.full,
    StaffRole.support: AreaAccess.view,
    StaffRole.catalog: AreaAccess.none,
  },
  PermissionArea.riders: {
    StaffRole.superAdmin: AreaAccess.full,
    StaffRole.sales: AreaAccess.none,
    StaffRole.support: AreaAccess.none,
    StaffRole.catalog: AreaAccess.none,
  },
  PermissionArea.reviewsContent: {
    StaffRole.superAdmin: AreaAccess.full,
    StaffRole.sales: AreaAccess.none,
    StaffRole.support: AreaAccess(AccessLevel.partial, AccessDetail.reviews),
    StaffRole.catalog: AreaAccess(AccessLevel.partial, AccessDetail.content),
  },
  PermissionArea.chat: {
    StaffRole.superAdmin: AreaAccess.full,
    StaffRole.sales: AreaAccess.none,
    StaffRole.support: AreaAccess.full,
    StaffRole.catalog: AreaAccess.none,
  },
  PermissionArea.reports: {
    StaffRole.superAdmin: AreaAccess.full,
    StaffRole.sales: AreaAccess(AccessLevel.partial, AccessDetail.salesAndRfq),
    StaffRole.support: AreaAccess.none,
    StaffRole.catalog: AreaAccess(AccessLevel.partial, AccessDetail.stock),
  },
  PermissionArea.settings: {
    StaffRole.superAdmin: AreaAccess.full,
    StaffRole.sales: AreaAccess.none,
    StaffRole.support: AreaAccess.none,
    StaffRole.catalog: AreaAccess.none,
  },
};

AreaAccess accessFor(StaffRole role, PermissionArea area) =>
    staffMatrix[area]![role]!;

/// Whether [role] sees [section] in the menu and may open its pages.
bool canOpen(StaffRole role, AdminSection section) {
  if (role == StaffRole.superAdmin) return true;
  final area = section.area;
  if (area == null) return true; // Dashboard: every active staff member.
  final access = accessFor(role, area);
  return switch (access.detail) {
    // "Reviews & content" splits into two sections.
    AccessDetail.reviews => section == AdminSection.reviews,
    AccessDetail.content => section == AdminSection.content,
    _ => access.level != AccessLevel.none,
  };
}

/// Sections [role] can open, in sidebar order.
List<AdminSection> sectionsFor(StaffRole role) => [
  for (final section in AdminSection.values)
    if (canOpen(role, section)) section,
];

/// Whether [role] may change things in [area] (a "Full" cell on A-14d), not
/// just look. The Edge Functions check the same before writing.
bool canEdit(StaffRole role, PermissionArea area) =>
    accessFor(role, area).level == AccessLevel.full;
