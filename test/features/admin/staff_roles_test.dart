import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:k_e_commerce/core/router/app_routes.dart';
import 'package:k_e_commerce/features/admin/domain/staff_outcome.dart';
import 'package:k_e_commerce/features/admin/domain/staff_role.dart';
import 'package:k_e_commerce/features/admin/presentation/staff_dialogs.dart';
import 'package:k_e_commerce/features/admin/presentation/staff_roles_page.dart';
import 'package:k_e_commerce/features/auth/presentation/set_password_page.dart';

import '../../helpers.dart';
import '../auth/auth_harness.dart' show settleToasts;
import '../auth/fake_auth_repository.dart';
import 'admin_harness.dart';
import 'fakes.dart';

Future<FakeAdminRepository> _openStaff(
  WidgetTester tester, {
  Size size = desktop,
}) async {
  final admin = FakeAdminRepository();
  await pumpAdmin(
    tester,
    email: 'chenda@kstore.example',
    size: size,
    location: AppRoutes.adminStaff,
    admin: admin,
  );
  return admin;
}

/// Whether a KButton can be tapped right now.
bool _enabled(WidgetTester tester, Key key) =>
    tester
        .widget<InkWell>(
          find.descendant(of: find.byKey(key), matching: find.byType(InkWell)),
        )
        .onTap !=
    null;

Finder _inDialog(Finder finder) =>
    find.descendant(of: find.byType(Dialog), matching: finder);

void main() {
  setUpAll(initializeDateFormatting);

  group('A-14d staff & roles', () {
    testWidgets('lists the staff with role, activity and status', (
      tester,
    ) async {
      await _openStaff(tester);
      expect(find.byType(StaffRolesPage), findsOneWidget);
      expect(find.text('Staff (5)'), findsOneWidget);
      expect(find.text('chenda@kstore.example · you'), findsOneWidget);
      expect(find.text('12 min ago'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('+855 92 115 408'), findsOneWidget);
      expect(find.text('Invite sent 21 Oct'), findsOneWidget);
      expect(find.text('Active'), findsNWidgets(4));
      expect(find.text('Pending'), findsOneWidget);
      // You can't edit yourself; pending invites get Resend instead.
      expect(_enabled(tester, const Key('edit-u-chenda')), isFalse);
      expect(_enabled(tester, const Key('edit-u-dalin')), isTrue);
      expect(find.byKey(const Key('resend-u-rachana')), findsOneWidget);
      expect(find.byKey(const Key('edit-u-rachana')), findsNothing);
    });

    testWidgets('shows the permission matrix and the server note', (
      tester,
    ) async {
      await _openStaff(tester);
      final matrix = find.byKey(const Key('permission-matrix'));
      for (final area in [
        'Orders',
        'RFQs & quotes',
        'Returns & refunds',
        'Products & inventory',
        'Customers & verification',
        'Riders & cash',
        'Reviews & content',
        'Support chat',
        'Reports',
        'Settings',
      ]) {
        expect(
          find.descendant(of: matrix, matching: find.text(area)),
          findsOneWidget,
          reason: area,
        );
      }
      expect(
        find.descendant(of: matrix, matching: find.text('Sales & RFQ')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: matrix, matching: find.text('Stock')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('No access'), findsWidgets);
      expect(
        find.text(
          'Permissions are enforced on the server for every request, not '
          'only hidden in the menu.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('works on a phone as cards', (tester) async {
      await _openStaff(tester, size: phone);
      expect(find.text('Staff (5)'), findsOneWidget);
      expect(find.text('Sales · 12 min ago'), findsOneWidget);
    });

    testWidgets('Resend sends a new invite', (tester) async {
      final admin = await _openStaff(tester);
      await tester.tap(find.byKey(const Key('resend-u-rachana')));
      await tester.pumpAndSettle();
      expect(admin.calls, ['resend u-rachana']);
      expect(
        find.text("Invite sent again. It's valid for 7 days."),
        findsOneWidget,
      );
      await settleToasts(tester);
    });

    testWidgets('other staff cannot open it', (tester) async {
      await pumpAdmin(
        tester,
        email: 'dalin@kstore.example',
        location: AppRoutes.adminStaff,
      );
      expect(find.byType(StaffRolesPage), findsNothing);
      expect(find.text('No access'), findsOneWidget);
    });
  });

  group('A-14e invite staff', () {
    Future<FakeAdminRepository> openInvite(WidgetTester tester) async {
      final admin = await _openStaff(tester);
      await tester.tap(find.byKey(const Key('invite-staff')));
      await tester.pumpAndSettle();
      expect(_inDialog(find.text('Invite staff')), findsOneWidget);
      return admin;
    }

    testWidgets('offers the four roles with what they cover', (tester) async {
      await openInvite(tester);
      for (final text in [
        'RFQs, quotes, business orders and verifications',
        'Chat, returns, refunds and order help',
        'Products, stock and home-screen content',
        'Everything, including payments and settings',
      ]) {
        expect(_inDialog(find.text(text)), findsOneWidget);
      }
      expect(
        _inDialog(
          find.text(
            "They'll get a link to set up sign-in. The invite expires in 7 "
            'days.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('checks the name and the email or phone first', (tester) async {
      final admin = await openInvite(tester);
      await tester.tap(find.byKey(const Key('send-invite')));
      await tester.pump();
      expect(find.text('Enter their full name.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('invite-name')), 'Rotha Kim');
      await tester.enterText(find.byKey(const Key('invite-contact')), '12');
      await tester.tap(find.byKey(const Key('send-invite')));
      await tester.pump();
      expect(
        find.text('Enter an email or a Cambodian mobile number.'),
        findsOneWidget,
      );
      expect(admin.calls, isEmpty);
    });

    testWidgets('sends a phone invite for the chosen role', (tester) async {
      final admin = await openInvite(tester);
      await tester.enterText(find.byKey(const Key('invite-name')), 'Rotha Kim');
      await tester.enterText(
        find.byKey(const Key('invite-contact')),
        '097 111 2233',
      );
      await tester.tap(find.byKey(const Key('role-support')));
      await tester.tap(find.byKey(const Key('send-invite')));
      await tester.pumpAndSettle();
      expect(admin.calls, ['invite Rotha Kim +855971112233 support']);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Invite sent to 097 111 2233.'), findsOneWidget);
      await settleToasts(tester);
    });

    testWidgets('says why the server refused', (tester) async {
      final admin = await openInvite(tester)
        ..next = const StaffRefused(StaffRefusal.accountExists);
      await tester.enterText(find.byKey(const Key('invite-name')), 'Dara Sok');
      await tester.enterText(
        find.byKey(const Key('invite-contact')),
        'dara@kstore.example',
      );
      await tester.tap(find.byKey(const Key('send-invite')));
      await tester.pumpAndSettle();
      expect(admin.calls, ['invite Dara Sok dara@kstore.example sales']);
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.text(
          'This email or phone already belongs to a customer, business or '
          'rider account.',
        ),
        findsOneWidget,
      );
    });
  });

  group('edit staff', () {
    Future<FakeAdminRepository> openEdit(WidgetTester tester) async {
      final admin = await _openStaff(tester);
      await tester.tap(find.byKey(const Key('edit-u-dalin')));
      await tester.pumpAndSettle();
      expect(find.text('Edit Dalin Chhay'), findsOneWidget);
      return admin;
    }

    testWidgets('a role change is confirmed first', (tester) async {
      final admin = await openEdit(tester);
      // Nothing to save until the role changes.
      expect(_enabled(tester, const Key('save-role')), isFalse);

      await tester.tap(_inDialog(find.byKey(const Key('role-catalog'))));
      await tester.pump();
      await tester.tap(find.byKey(const Key('save-role')));
      await tester.pumpAndSettle();
      expect(find.text('Change role?'), findsOneWidget);
      expect(
        find.text(
          'Dalin Chhay becomes Catalog and can only open what that role '
          'allows.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Change role'));
      await tester.pumpAndSettle();
      expect(admin.calls, ['update_role u-dalin catalog']);
      expect(find.text('Role updated.'), findsOneWidget);
      await settleToasts(tester);
    });

    testWidgets('removing asks first and can be cancelled', (tester) async {
      final admin = await openEdit(tester);
      await tester.tap(find.byKey(const Key('remove-staff')));
      await tester.pumpAndSettle();
      expect(find.text('Remove Dalin Chhay?'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(admin.calls, isEmpty);

      await tester.tap(find.byKey(const Key('remove-staff')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(admin.calls, ['remove u-dalin']);
      expect(
        find.text('Dalin Chhay no longer has staff access.'),
        findsOneWidget,
      );
      await settleToasts(tester);
    });

    testWidgets('keeps the dialog open when the server refuses', (
      tester,
    ) async {
      final admin = await openEdit(tester)
        ..next = const StaffRefused(StaffRefusal.lastSuperAdmin);
      await tester.tap(find.byKey(const Key('remove-staff')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(admin.calls, ['remove u-dalin']);
      expect(find.byType(EditStaffDialog), findsOneWidget);
      expect(
        find.text('Keep at least one active super admin.'),
        findsOneWidget,
      );
    });
  });

  group('set password', () {
    testWidgets('email invitees set a password, then land in the back office', (
      tester,
    ) async {
      final auth = FakeAuthRepository(
        accounts: {
          'sokim@kstore.example': staffProfile(
            'u-sokim',
            'Sokim Ou',
            StaffRole.catalog,
            needsPassword: true,
          ),
        },
      );
      await pumpAdmin(tester, email: 'sokim@kstore.example', auth: auth);
      expect(find.byType(SetPasswordPage), findsOneWidget);

      await tester.enterText(find.byKey(const Key('set-password')), 'short');
      await tester.tap(find.byKey(const Key('set-password-save')));
      await tester.pump();
      expect(find.text('Use at least 8 characters.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('set-password')),
        'kstore-2026',
      );
      await tester.enterText(
        find.byKey(const Key('set-password-confirm')),
        'kstore-2025',
      );
      await tester.tap(find.byKey(const Key('set-password-save')));
      await tester.pump();
      expect(find.text("The passwords don't match."), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('set-password-confirm')),
        'kstore-2026',
      );
      await tester.tap(find.byKey(const Key('set-password-save')));
      await tester.pumpAndSettle();
      expect(auth.passwordsSet, ['kstore-2026']);
      expect(find.text(adminHome), findsOneWidget);
    });
  });

  test('invite roles follow A-14e', () {
    expect(inviteRoleOrder.map((r) => r.dbName), [
      'sales',
      'support',
      'catalog',
      'super_admin',
    ]);
  });
}
