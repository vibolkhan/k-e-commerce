import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:k_e_commerce/core/l10n/generated/app_localizations.dart';
import 'package:k_e_commerce/core/router/app_role.dart';
import 'package:k_e_commerce/core/router/app_router.dart';
import 'package:k_e_commerce/core/router/app_routes.dart';
import 'package:k_e_commerce/core/time/cutoff.dart';
import 'package:k_e_commerce/features/admin/domain/admin_section.dart';
import 'package:k_e_commerce/features/admin/domain/staff_member.dart';
import 'package:k_e_commerce/features/admin/domain/staff_outcome.dart';
import 'package:k_e_commerce/features/admin/domain/staff_permissions.dart';
import 'package:k_e_commerce/features/admin/domain/staff_role.dart';
import 'package:k_e_commerce/features/admin/presentation/admin_labels.dart';
import 'package:k_e_commerce/features/admin/presentation/staff_dialogs.dart';
import 'package:k_e_commerce/features/auth/domain/profile.dart';

import 'fakes.dart';

void main() {
  group('A-14d matrix', () {
    test('each role sees exactly its sections, in sidebar order', () {
      expect(sectionsFor(StaffRole.superAdmin), AdminSection.values);
      expect(sectionsFor(StaffRole.sales), [
        AdminSection.dashboard,
        AdminSection.orders,
        AdminSection.rfqs,
        AdminSection.catalog,
        AdminSection.inventory,
        AdminSection.customers,
        AdminSection.reports,
      ]);
      expect(sectionsFor(StaffRole.support), [
        AdminSection.dashboard,
        AdminSection.orders,
        AdminSection.returns,
        AdminSection.catalog,
        AdminSection.inventory,
        AdminSection.customers,
        AdminSection.reviews,
        AdminSection.chat,
      ]);
      expect(sectionsFor(StaffRole.catalog), [
        AdminSection.dashboard,
        AdminSection.catalog,
        AdminSection.inventory,
        AdminSection.content,
        AdminSection.reports,
      ]);
    });

    test('every area has a cell for every role', () {
      for (final area in PermissionArea.values) {
        for (final role in StaffRole.values) {
          expect(() => accessFor(role, area), returnsNormally);
        }
      }
      expect(
        accessFor(StaffRole.support, PermissionArea.orders).level,
        AccessLevel.view,
      );
      expect(
        accessFor(StaffRole.catalog, PermissionArea.reports).detail,
        AccessDetail.stock,
      );
    });

    test('only super admins open settings', () {
      for (final role in StaffRole.values) {
        expect(
          canOpen(role, AdminSection.settings),
          role == StaffRole.superAdmin,
        );
      }
    });
  });

  group('AdminSection.forPath', () {
    test('maps back-office paths to sections', () {
      expect(AdminSection.forPath('/admin'), AdminSection.dashboard);
      expect(AdminSection.forPath('/admin/orders'), AdminSection.orders);
      expect(
        AdminSection.forPath('/admin/settings/staff'),
        AdminSection.settings,
      );
      expect(AdminSection.forPath('/admin/more'), isNull);
      expect(AdminSection.forPath('/admin/inbox'), isNull);
      expect(AdminSection.forPath('/customer/orders'), isNull);
    });
  });

  group('adminRedirect', () {
    test('a role only opens its sections', () {
      for (final role in StaffRole.values) {
        for (final section in AdminSection.values) {
          expect(
            adminRedirect(role, section.path),
            canOpen(role, section) ? isNull : AppRoutes.forbidden,
            reason: '${role.name} ${section.name}',
          );
        }
      }
      expect(
        adminRedirect(StaffRole.sales, AppRoutes.adminStaff),
        AppRoutes.forbidden,
      );
    });

    test('More and the inbox are open to every active member', () {
      for (final role in StaffRole.values) {
        expect(adminRedirect(role, AppRoutes.adminMore), isNull);
        expect(adminRedirect(role, AppRoutes.inbox(AppRoutes.admin)), isNull);
      }
    });

    test('F09: viewers open products; only editors create or import', () {
      for (final role in StaffRole.values) {
        final edits = role == StaffRole.superAdmin || role == StaffRole.catalog;
        expect(adminRedirect(role, AppRoutes.adminCatalog), isNull);
        expect(adminRedirect(role, AppRoutes.adminProduct('p-1')), isNull);
        for (final path in [
          AppRoutes.adminProductNew,
          AppRoutes.adminCatalogImport,
        ]) {
          expect(
            adminRedirect(role, path),
            edits ? isNull : AppRoutes.adminCatalog,
            reason: '$role $path',
          );
        }
      }
    });

    test('no active membership: only the pending page', () {
      expect(adminRedirect(null, AppRoutes.admin), AppRoutes.adminPending);
      expect(adminRedirect(null, '/admin/orders'), AppRoutes.adminPending);
      expect(adminRedirect(null, AppRoutes.adminPending), isNull);
      expect(
        adminRedirect(StaffRole.catalog, AppRoutes.adminPending),
        AppRoutes.admin,
      );
    });

    test('paths outside the back office are left alone', () {
      expect(adminRedirect(null, AppRoutes.customer), isNull);
      expect(adminRedirect(StaffRole.sales, AppRoutes.signIn), isNull);
    });
  });

  test('email invitees set a password before anything else', () {
    const profile = Profile(
      id: 'x',
      role: AppRole.admin,
      fullName: 'Sokim Ou',
      needsPassword: true,
    );
    expect(
      accountRedirect(profile, AppRoutes.admin),
      AppRoutes.signInSetPassword,
    );
    expect(accountRedirect(profile, AppRoutes.signInSetPassword), isNull);
  });

  group('Cutoff', () {
    test('parses HH:mm, falls back to 15:00', () {
      expect(Cutoff.parse('14:30').hour, 14);
      expect(Cutoff.parse('14:30').minute, 30);
      expect(Cutoff.parse(null).hour, 15);
      expect(Cutoff.parse('25:00').hour, 15);
      expect(Cutoff.parse('3pm').hour, 15);
    });

    test('counts down in Phnom Penh time and stops at the cut-off', () {
      const cutoff = Cutoff.standard;
      expect(cutoff.remaining(adminNow), const Duration(hours: 5));
      // 14:59 local is 07:59 UTC.
      expect(
        cutoff.remaining(DateTime.utc(2026, 10, 27, 7, 59)),
        const Duration(minutes: 1),
      );
      expect(cutoff.remaining(DateTime.utc(2026, 10, 27, 8)), isNull);
      expect(cutoff.remaining(DateTime.utc(2026, 10, 27, 16)), isNull);
      // 23:30 UTC on the 26th is already 06:30 on the 27th in Phnom Penh.
      expect(
        cutoff.remaining(DateTime.utc(2026, 10, 26, 23, 30)),
        const Duration(hours: 8, minutes: 30),
      );
    });
  });

  group('labels', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    setUpAll(initializeDateFormatting);

    test('durations', () {
      expect(
        durationLabel(l10n, const Duration(hours: 4, minutes: 35)),
        '4h 35m',
      );
      expect(durationLabel(l10n, const Duration(seconds: 90)), '2m');
    });

    test('last active', () {
      String label(StaffMember m) => lastActiveLabel(l10n, m, now: adminNow);
      final [me, dalin, _, visal, rachana] = seedStaff;
      expect(label(me), 'Now');
      expect(label(dalin), '12 min ago');
      expect(label(visal), 'Yesterday');
      expect(label(rachana), 'Invite sent 21 Oct');
    });

    test('phones show in the local format', () {
      expect(staffContactLabel(seedStaff.last), '+855 92 115 408');
    });
  });

  test('contacts are normalised like the server does', () {
    expect(normalizeStaffContact(' Sokim@K.example '), 'sokim@k.example');
    expect(normalizeStaffContact('012 345 678'), '+85512345678');
    expect(normalizeStaffContact('12'), isNull);
    expect(normalizeStaffContact('a@b'), isNull);
  });

  test('staff-manage answers', () {
    expect(
      (StaffOutcome.fromJson({'status': 'invited'}) as StaffDone).action,
      StaffAction.invited,
    );
    expect(
      (StaffOutcome.fromJson({'status': 'invalid', 'field': 'contact'})
              as StaffInvalid)
          .field,
      StaffField.contact,
    );
    expect(
      (StaffOutcome.fromJson({'status': 'last_super_admin'}) as StaffRefused)
          .reason,
      StaffRefusal.lastSuperAdmin,
    );
    expect(
      (StaffOutcome.fromJson({'status': 'brand_new'}) as StaffRefused).reason,
      StaffRefusal.unknown,
    );
  });

  test('rows from the database', () {
    final member = StaffMember.fromRow({
      'profile_id': 'p',
      'full_name': 'Rachana Ty',
      'email': null,
      'phone': '+85592115408',
      'staff_role': 'support',
      'status': 'invited',
      'invited_at': '2026-10-21T03:00:00+00:00',
      'invite_expires_at': '2026-10-28T03:00:00+00:00',
      'is_me': false,
    });
    expect(member.role, StaffRole.support);
    expect(member.isPending, isTrue);
    expect(member.isExpired(adminNow), isFalse);
    expect(member.isExpired(DateTime.utc(2026, 10, 29)), isTrue);

    final profile = Profile.fromRow({
      'id': 'p',
      'role': 'staff',
      'staff_members': {'staff_role': 'catalog', 'status': 'active'},
    });
    expect(profile.staffRole, StaffRole.catalog);
    expect(profile.staffStatus, StaffStatus.active);
    expect(Profile.fromRow({'id': 'c', 'role': 'customer'}).staffRole, isNull);
  });
}
