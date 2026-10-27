import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/router/app_router.dart';
import 'package:k_e_commerce/features/admin/domain/admin_section.dart';
import 'package:k_e_commerce/features/admin/domain/staff_permissions.dart';
import 'package:k_e_commerce/features/admin/domain/staff_role.dart';
import 'package:k_e_commerce/features/admin/presentation/admin_pages.dart';
import 'package:k_e_commerce/features/admin/presentation/admin_sidebar.dart';

import '../../helpers.dart';
import '../auth/fake_auth_repository.dart';
import 'admin_harness.dart';
import 'fakes.dart';

const _emails = {
  StaffRole.superAdmin: 'chenda@kstore.example',
  StaffRole.sales: 'dalin@kstore.example',
  StaffRole.support: 'sophea@kstore.example',
  StaffRole.catalog: 'visal@kstore.example',
};

Finder _navLink(AdminSection section) =>
    find.byKey(Key('admin-nav-${section.name}'));

void main() {
  group('desktop sidebar', () {
    for (final MapEntry(key: role, value: email) in _emails.entries) {
      testWidgets('${role.name} sees only their sections', (tester) async {
        final container = await pumpAdmin(tester, email: email);
        expect(find.text(adminHome), findsOneWidget);
        final allowed = sectionsFor(role);
        for (final section in AdminSection.values) {
          expect(
            _navLink(section),
            allowed.contains(section) ? findsOneWidget : findsNothing,
            reason: section.name,
          );
        }

        // Deep links to anything else are refused, like the server would.
        final router = container.read(routerProvider);
        for (final section in AdminSection.values) {
          router.go(section.path);
          await tester.pumpAndSettle();
          expect(
            find.text('No access'),
            allowed.contains(section) ? findsNothing : findsOneWidget,
            reason: section.name,
          );
        }
      });
    }

    testWidgets('groups, badges and navigation', (tester) async {
      final admin = FakeAdminRepository(
        badges: {AdminSection.orders: 12, AdminSection.rfqs: 3},
      );
      await pumpAdmin(tester, email: 'chenda@kstore.example', admin: admin);
      final sidebar = find.byType(AdminSidebar);
      for (final group in ['SALES', 'CATALOG', 'PEOPLE', 'INSIGHTS']) {
        expect(
          find.descendant(of: sidebar, matching: find.text(group)),
          findsOneWidget,
        );
      }
      expect(find.bySemanticsLabel('Orders, 12 new'), findsOneWidget);
      expect(find.bySemanticsLabel('RFQs & quotes, 3 new'), findsOneWidget);

      await tester.tap(_navLink(AdminSection.riders));
      await tester.pumpAndSettle();
      expect(
        find.text('This screen (A-08) arrives in a later update.'),
        findsOneWidget,
      );
    });

    testWidgets('catalog staff get no sales or people group', (tester) async {
      await pumpAdmin(tester, email: 'visal@kstore.example');
      final sidebar = find.byType(AdminSidebar);
      expect(
        find.descendant(of: sidebar, matching: find.text('SALES')),
        findsNothing,
      );
      expect(
        find.descendant(of: sidebar, matching: find.text('PEOPLE')),
        findsNothing,
      );
      expect(
        find.descendant(of: sidebar, matching: find.text('CATALOG')),
        findsOneWidget,
      );
    });
  });

  group('top bar', () {
    testWidgets('counts down to the cut-off, then says next day', (
      tester,
    ) async {
      await pumpAdmin(
        tester,
        email: 'dalin@kstore.example',
        now: adminNow.add(const Duration(minutes: 25)),
      );
      expect(find.text('Same-day cut-off in 4h 35m'), findsOneWidget);
    });

    testWidgets('after 3 PM it says next-day delivery', (tester) async {
      await pumpAdmin(
        tester,
        email: 'dalin@kstore.example',
        now: DateTime.utc(2026, 10, 27, 9),
      );
      expect(find.text('Cut-off passed · next-day delivery'), findsOneWidget);
    });

    testWidgets('shows who is signed in; "/" focuses search', (tester) async {
      await pumpAdmin(tester, email: 'sophea@kstore.example');
      expect(find.text('Sophea Mao'), findsOneWidget);
      expect(find.text('Support'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.pump();
      final field = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('admin-search')),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.focusNode.hasFocus, isTrue);
    });

    testWidgets('the account menu signs out after confirming', (tester) async {
      final auth = FakeAuthRepository(accounts: {...staffAccounts});
      await pumpAdmin(tester, email: 'dalin@kstore.example', auth: auth);
      await tester.tap(find.byKey(const Key('admin-account-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin-menu-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out').last);
      await tester.pumpAndSettle();
      expect(auth.signOuts, 1);
      expect(find.text('Customer home'), findsOneWidget);
    });
  });

  group('phone', () {
    testWidgets('bottom nav: Dashboard, Orders, RFQs, Chat, More', (
      tester,
    ) async {
      final admin = FakeAdminRepository(badges: {AdminSection.chat: 2});
      await pumpAdmin(
        tester,
        email: 'chenda@kstore.example',
        size: phone,
        admin: admin,
      );
      expect(find.byType(AdminSidebar), findsNothing);
      for (final tab in ['Dashboard', 'Orders', 'RFQs', 'Chat', 'More']) {
        expect(find.text(tab), findsWidgets, reason: tab);
      }
      expect(find.bySemanticsLabel(RegExp('Chat, 2 new')), findsOneWidget);
      // Phones have no top bar, so the dashboard carries the countdown.
      expect(find.text('Same-day cut-off in 5h 0m'), findsOneWidget);
    });

    testWidgets('catalog staff get Dashboard and More only', (tester) async {
      await pumpAdmin(tester, email: 'visal@kstore.example', size: phone);
      expect(find.text('Orders'), findsNothing);
      expect(find.text('RFQs'), findsNothing);
      expect(find.text('Chat'), findsNothing);
      expect(find.text('More'), findsOneWidget);
    });

    testWidgets('M-05 More lists the other permitted sections', (tester) async {
      await pumpAdmin(tester, email: 'sophea@kstore.example', size: phone);
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminMorePage), findsOneWidget);
      expect(
        find.text('Catalog editing and settings work best on desktop.'),
        findsOneWidget,
      );
      for (final section in [
        AdminSection.returns,
        AdminSection.catalog,
        AdminSection.inventory,
        AdminSection.customers,
        AdminSection.reviews,
      ]) {
        expect(_navLink(section), findsOneWidget, reason: section.name);
      }
      for (final section in [
        AdminSection.rfqs,
        AdminSection.riders,
        AdminSection.content,
        AdminSection.reports,
        AdminSection.settings,
      ]) {
        expect(_navLink(section), findsNothing, reason: section.name);
      }

      await tester.tap(_navLink(AdminSection.returns));
      await tester.pumpAndSettle();
      expect(
        find.text('This screen (A-09) arrives in a later update.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('staff whose invite lapsed only see the pending page', (
    tester,
  ) async {
    final container = await pumpAdmin(tester, email: 'rachana@kstore.example');
    expect(find.byType(AdminPendingPage), findsOneWidget);
    expect(find.byType(AdminSidebar), findsNothing);
    container.read(routerProvider).go('/admin/returns');
    await tester.pumpAndSettle();
    expect(find.byType(AdminPendingPage), findsOneWidget);
  });
}
