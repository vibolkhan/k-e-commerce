import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/time/date_format.dart';
import '../../../core/time/phnom_penh_time.dart';
import '../../../core/ui/k_ui.dart';
import '../../auth/domain/phone_number.dart';
import '../domain/admin_section.dart';
import '../domain/staff_member.dart';
import '../domain/staff_outcome.dart';
import '../domain/staff_permissions.dart';
import '../domain/staff_role.dart';

String staffRoleLabel(AppLocalizations l10n, StaffRole role) => switch (role) {
  StaffRole.superAdmin => l10n.staffRoleSuperAdmin,
  StaffRole.sales => l10n.staffRoleSales,
  StaffRole.support => l10n.staffRoleSupport,
  StaffRole.catalog => l10n.staffRoleCatalog,
};

/// A-14e role cards.
String staffRoleDescription(AppLocalizations l10n, StaffRole role) =>
    switch (role) {
      StaffRole.superAdmin => l10n.staffRoleSuperAdminDesc,
      StaffRole.sales => l10n.staffRoleSalesDesc,
      StaffRole.support => l10n.staffRoleSupportDesc,
      StaffRole.catalog => l10n.staffRoleCatalogDesc,
    };

String sectionLabel(AppLocalizations l10n, AdminSection section) =>
    switch (section) {
      AdminSection.dashboard => l10n.adminSectionDashboard,
      AdminSection.orders => l10n.adminSectionOrders,
      AdminSection.rfqs => l10n.adminSectionRfqs,
      AdminSection.returns => l10n.adminSectionReturns,
      AdminSection.catalog => l10n.adminSectionCatalog,
      AdminSection.inventory => l10n.adminSectionInventory,
      AdminSection.content => l10n.adminSectionContent,
      AdminSection.customers => l10n.adminSectionCustomers,
      AdminSection.riders => l10n.adminSectionRiders,
      AdminSection.reviews => l10n.adminSectionReviews,
      AdminSection.chat => l10n.adminSectionChat,
      AdminSection.reports => l10n.adminSectionReports,
      AdminSection.settings => l10n.adminSectionSettings,
    };

KIconData sectionIcon(AdminSection section) => switch (section) {
  AdminSection.dashboard => KIcons.dashboard,
  AdminSection.orders => KIcons.orders,
  AdminSection.rfqs => KIcons.quote,
  AdminSection.returns => KIcons.returnItem,
  AdminSection.catalog => KIcons.tag,
  AdminSection.inventory => KIcons.stock,
  AdminSection.content => KIcons.image,
  AdminSection.customers => KIcons.people,
  AdminSection.riders => KIcons.rider,
  AdminSection.reviews => KIcons.star,
  AdminSection.chat => KIcons.chat,
  AdminSection.reports => KIcons.reports,
  AdminSection.settings => KIcons.settings,
};

/// Neutral (blue) counts are queues; red ones need attention now
/// (CmpAdminSidebar).
bool sectionBadgeBlue(AdminSection section) => switch (section) {
  AdminSection.rfqs ||
  AdminSection.returns ||
  AdminSection.customers ||
  AdminSection.reviews => true,
  _ => false,
};

String groupLabel(AppLocalizations l10n, AdminGroup group) => switch (group) {
  AdminGroup.sales => l10n.adminGroupSales,
  AdminGroup.catalog => l10n.adminGroupCatalog,
  AdminGroup.people => l10n.adminGroupPeople,
  AdminGroup.insights => l10n.adminGroupInsights,
};

String areaLabel(AppLocalizations l10n, PermissionArea area) => switch (area) {
  PermissionArea.orders => l10n.areaOrders,
  PermissionArea.rfqs => l10n.areaRfqs,
  PermissionArea.returns => l10n.areaReturns,
  PermissionArea.products => l10n.areaProducts,
  PermissionArea.customers => l10n.areaCustomers,
  PermissionArea.riders => l10n.areaRiders,
  PermissionArea.reviewsContent => l10n.areaReviewsContent,
  PermissionArea.chat => l10n.areaChat,
  PermissionArea.reports => l10n.areaReports,
  PermissionArea.settings => l10n.areaSettings,
};

/// The A-14d cell text; [AccessLevel.none] shows a dash with this as its
/// spoken label.
String accessLabel(AppLocalizations l10n, AreaAccess access) =>
    switch (access.detail) {
      AccessDetail.reviews => l10n.accessReviews,
      AccessDetail.content => l10n.accessContent,
      AccessDetail.salesAndRfq => l10n.accessSalesRfq,
      AccessDetail.stock => l10n.accessStock,
      null => switch (access.level) {
        AccessLevel.full => l10n.accessFull,
        AccessLevel.view => l10n.accessView,
        AccessLevel.partial || AccessLevel.none => l10n.accessNone,
      },
    };

/// What a refused staff-manage call tells the super admin.
String staffRefusalMessage(AppLocalizations l10n, StaffRefusal reason) =>
    switch (reason) {
      StaffRefusal.forbidden => l10n.staffErrForbidden,
      StaffRefusal.accountExists => l10n.staffErrAccountExists,
      StaffRefusal.alreadyStaff => l10n.staffErrAlreadyStaff,
      StaffRefusal.notFound => l10n.staffErrNotFound,
      StaffRefusal.notInvited => l10n.staffErrNotInvited,
      StaffRefusal.self => l10n.staffErrSelf,
      StaffRefusal.lastSuperAdmin => l10n.staffErrLastSuperAdmin,
      StaffRefusal.sendFailed => l10n.staffErrSendFailed,
      StaffRefusal.unknown => l10n.staffErrUnknown,
    };

/// "4h 35m" / "12m".
String durationLabel(AppLocalizations l10n, Duration left) {
  final minutes = (left.inSeconds / 60).ceil();
  final hours = minutes ~/ 60;
  return hours > 0
      ? l10n.adminDurationHm(hours, minutes % 60)
      : l10n.adminDurationM(minutes);
}

/// A-14d "Last active": "Now", "12 min ago", "3 h ago", "Yesterday",
/// "21 Oct"; pending invites say when they were sent.
String lastActiveLabel(
  AppLocalizations l10n,
  StaffMember member, {
  required DateTime now,
}) {
  if (member.isPending) {
    final sent = member.invitedAt;
    return sent == null
        ? l10n.staffNeverSignedIn
        : l10n.staffInviteSent(formatDayMonth(l10n, sent));
  }
  if (member.isMe) return l10n.staffNow;
  final last = member.lastSignInAt;
  if (last == null) return l10n.staffNeverSignedIn;
  final ago = now.difference(last);
  if (ago.inMinutes < 1) return l10n.staffNow;
  if (ago.inMinutes < 60) return l10n.staffMinutesAgo(ago.inMinutes);
  return switch (phnomPenhDaysBetween(last, now)) {
    0 => l10n.staffHoursAgo(ago.inHours),
    1 => l10n.staffYesterday,
    _ => formatDayMonth(l10n, last),
  };
}

/// The email, else the phone as "+855 92 115 408".
String staffContactLabel(StaffMember member) =>
    member.email ??
    (member.phone == null ? '' : KhPhone.display(member.phone!));
