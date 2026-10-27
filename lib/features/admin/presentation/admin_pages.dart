import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_role.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/ui/k_ui.dart';
import '../../account/presentation/account_actions.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../settings/presentation/language_sheet.dart';
import '../../shell/presentation/role_home_page.dart';
import '../domain/admin_section.dart';
import '../domain/staff_permissions.dart';
import 'admin_labels.dart';
import 'admin_providers.dart';
import 'admin_shell.dart';
import 'admin_sidebar.dart';
import 'admin_top_bar.dart';

/// A section whose screens arrive with a later task. The dashboard (A-01 /
/// M-01) shows the cut-off on phones, where there is no top bar.
class AdminSectionPage extends StatelessWidget {
  const AdminSectionPage({super.key, required this.section});

  final AdminSection section;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = sectionLabel(l10n, section);
    return AdminPage(
      title: title,
      showBack: AdminBottomNav.tabs.contains(section) == false,
      children: [
        if (section == AdminSection.dashboard && !isAdminWide(context)) ...[
          const Align(alignment: Alignment.centerLeft, child: CutoffPill()),
          const SizedBox(height: 16),
        ],
        KEmptyState(
          icon: sectionIcon(section),
          title: title,
          message: l10n.placeholderBody(section.screenId),
        ),
        if (kDebugMode && section == AdminSection.dashboard) ...[
          const SizedBox(height: 24),
          const DevRoleSwitcher(current: AppRole.admin),
        ],
      ],
    );
  }
}

/// M-05: everything that isn't a bottom-nav tab, plus language and sign out
/// (the phone layout has no account menu).
class AdminMorePage extends ConsumerWidget {
  const AdminMorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(currentProfileProvider).value;
    final role = ref.watch(currentStaffRoleProvider);
    final badges = ref.watch(adminBadgesProvider).value ?? const {};
    final sections = [
      for (final section in role == null ? <AdminSection>[] : sectionsFor(role))
        if (!AdminBottomNav.tabs.contains(section)) section,
    ];
    // M-05 groups: Sales, Catalog, People, then "Insights & settings".
    final groups = <AdminGroup, List<AdminSection>>{};
    for (final section in sections) {
      groups.putIfAbsent(section.group!, () => []).add(section);
    }

    return AdminPage(
      title: l10n.adminMoreTitle,
      children: [
        Row(
          children: [
            KAvatar(initialsOf(profile?.fullName)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile?.fullName ?? l10n.roleAdmin,
                    style: k.text.title,
                  ),
                  if (role != null)
                    Text(
                      staffRoleLabel(l10n, role),
                      style: k.text.caption.copyWith(color: k.colors.muted),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        KBanner(message: l10n.adminMoreDesktopTip, icon: KIcons.info),
        for (final MapEntry(key: group, value: items) in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 6),
            child: Semantics(
              header: true,
              child: KOverline(
                group == AdminGroup.insights
                    ? l10n.adminGroupInsightsSettings
                    : groupLabel(l10n, group),
              ),
            ),
          ),
          for (final section in items)
            AdminNavLink(
              section: section,
              selected: false,
              badge: badges[section],
              onTap: () => context.go(section.path),
            ),
        ],
        const SizedBox(height: 20),
        KList(
          children: [
            KListRow(
              icon: KIcons.language,
              title: l10n.languageTitle,
              onTap: () => showLanguageSheet(context),
            ),
            if (profile != null)
              KListRow(
                key: const Key('admin-more-sign-out'),
                icon: KIcons.back,
                title: l10n.authSignOut,
                onTap: () => confirmSignOut(context, ref),
              ),
          ],
        ),
      ],
    );
  }
}

/// Staff whose invite has expired or whose access was removed: no menu,
/// only what to do next.
class AdminPendingPage extends ConsumerWidget {
  const AdminPendingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final signedIn = ref.watch(currentProfileProvider).value != null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: KEmptyState(
              icon: KIcons.lock,
              title: l10n.adminPendingTitle,
              message: l10n.adminPendingBody,
              action: signedIn
                  ? KButton.outline(
                      key: const Key('admin-pending-sign-out'),
                      label: l10n.authSignOut,
                      onPressed: () => confirmSignOut(context, ref),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// A-14 "Store setup" links. Only Staff & roles is built in F08; the others
/// arrive with the settings task.
enum SettingsPage { zones, payments, store, staff, audit }

String settingsPageLabel(AppLocalizations l10n, SettingsPage page) =>
    switch (page) {
      SettingsPage.zones => l10n.adminSettingsZones,
      SettingsPage.payments => l10n.adminSettingsPayments,
      SettingsPage.store => l10n.adminSettingsStore,
      SettingsPage.staff => l10n.adminSettingsStaff,
      SettingsPage.audit => l10n.adminSettingsAudit,
    };

void openSettingsPage(BuildContext context, SettingsPage page) {
  if (page == SettingsPage.staff) {
    context.go(AppRoutes.adminStaff);
  } else {
    showComingSoon(context);
  }
}

/// A-14 Settings: the Store setup list.
class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AdminPage(
      title: l10n.adminSectionSettings,
      showBack: true,
      children: [
        KList(
          children: [
            for (final page in SettingsPage.values)
              KListRow(
                key: Key('settings-${page.name}'),
                title: settingsPageLabel(l10n, page),
                onTap: () => openSettingsPage(context, page),
              ),
          ],
        ),
      ],
    );
  }
}

/// The A-14 sub-navigation beside a settings page on desktop.
class SettingsNav extends StatelessWidget {
  const SettingsNav({super.key, required this.current});

  final SettingsPage current;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    Widget link(String label, bool selected, VoidCallback onTap, Key key) =>
        Semantics(
          button: true,
          selected: selected,
          child: Material(
            color: selected ? c.tint2 : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: Container(
                height: 44,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  label,
                  style: k.text.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? c.primaryInk : c.ink2,
                  ),
                ),
              ),
            ),
          ),
        );
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: KOverline(l10n.adminSettingsStoreSetup),
          ),
          link(
            l10n.adminSectionSettings,
            false,
            () => context.go(AdminSection.settings.path),
            const Key('settings-nav-settings'),
          ),
          for (final page in SettingsPage.values)
            link(
              settingsPageLabel(l10n, page),
              page == current,
              () => openSettingsPage(context, page),
              Key('settings-nav-${page.name}'),
            ),
        ],
      ),
    );
  }
}
