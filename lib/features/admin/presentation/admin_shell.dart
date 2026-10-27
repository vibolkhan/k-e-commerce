import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/ui/k_ui.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../domain/admin_section.dart';
import '../domain/staff_permissions.dart';
import 'admin_labels.dart';
import 'admin_providers.dart';
import 'admin_sidebar.dart';
import 'admin_top_bar.dart';

/// Desktop layout (sidebar + top bar) from this width; below it the phone
/// layout with the admin bottom nav.
const adminWideBreakpoint = 1024.0;

bool isAdminWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= adminWideBreakpoint;

/// The frame every back-office page sits in. Only the sections the staff
/// role may open are offered; the router refuses the rest.
class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key, required this.location, required this.child});

  /// The current path, to highlight its section.
  final String location;
  final Widget child;

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  final _searchFocus = FocusNode();
  late final Timer _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(
      badgeRefresh,
      (_) => ref.invalidate(adminBadgesProvider),
    );
  }

  @override
  void didUpdateWidget(AdminShell old) {
    super.didUpdateWidget(old);
    // Counts change as staff work through a list; refresh on navigation,
    // after this build.
    if (old.location != widget.location) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(adminBadgesProvider);
      });
    }
  }

  @override
  void dispose() {
    _refresh.cancel();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = AdminSection.forPath(widget.location);
    if (!isAdminWide(context)) {
      return Scaffold(
        body: widget.child,
        bottomNavigationBar: AdminBottomNav(location: widget.location),
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.slash): () {
          if (!_searchFocus.hasFocus) _searchFocus.requestFocus();
        },
      },
      // Keeps keyboard focus inside the shell so "/" reaches the shortcut.
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminSidebar(current: current),
              Expanded(
                child: Column(
                  children: [
                    AdminTopBar(searchFocus: _searchFocus),
                    // The nested navigator's route blocks the semantics of
                    // everything painted before it in its container; give
                    // it its own so the sidebar and top bar stay readable.
                    Expanded(
                      child: Semantics(container: true, child: widget.child),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CmpAdminNav: Dashboard, Orders, RFQs, Chat, More — without the tabs the
/// role can't open. Every other section is reached from More (M-05).
class AdminBottomNav extends ConsumerWidget {
  const AdminBottomNav({super.key, required this.location});

  final String location;

  static const tabs = [
    AdminSection.dashboard,
    AdminSection.orders,
    AdminSection.rfqs,
    AdminSection.chat,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final role = ref.watch(currentStaffRoleProvider);
    final badges = ref.watch(adminBadgesProvider).value ?? const {};
    final shown = [
      for (final tab in tabs)
        if (role != null && canOpen(role, tab)) tab,
    ];
    final current = AdminSection.forPath(location);
    final index = current == null ? -1 : shown.indexOf(current);
    final label = {
      AdminSection.dashboard: l10n.navDashboard,
      AdminSection.orders: l10n.navOrders,
      AdminSection.rfqs: l10n.navRfqs,
      AdminSection.chat: l10n.navChat,
    };
    return KBottomNav(
      currentIndex: index < 0 ? shown.length : index,
      onTap: (i) =>
          context.go(i < shown.length ? shown[i].path : AppRoutes.adminMore),
      items: [
        for (final tab in shown)
          KNavItem(
            icon: sectionIcon(tab),
            label: label[tab]!,
            badge: badges[tab],
            badgeBlue: sectionBadgeBlue(tab),
          ),
        KNavItem(icon: KIcons.more, label: l10n.navMore),
      ],
    );
  }
}

/// A back-office page: on desktop a 26 px title over a padded body (the
/// shell supplies sidebar and top bar); on phones an app bar with the bell.
class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.showBack = false,
    this.parent,
  });

  final String title;
  final List<Widget> children;

  /// Buttons beside the title (desktop) or under the app bar (phone).
  final List<Widget> actions;

  /// Phone only: a back button to [parent] (sub-pages of More/Settings).
  final bool showBack;
  final String? parent;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    if (isAdminWide(context)) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 16,
            runSpacing: 12,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: k.text.h1.copyWith(
                    fontSize: 26,
                    height: 34 / 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (actions.isNotEmpty)
                Wrap(spacing: 12, runSpacing: 8, children: actions),
            ],
          ),
          const SizedBox(height: 24),
          ...children,
        ],
      );
    }
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: KAppBar(
            title: title,
            centerTitle: false,
            line: true,
            showBack: showBack,
            onBack: () => context.canPop()
                ? context.pop()
                : context.go(parent ?? AppRoutes.adminMore),
            actions: const [NotificationBell(shell: AppRoutes.admin)],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (actions.isNotEmpty) ...[
                Wrap(spacing: 12, runSpacing: 8, children: actions),
                const SizedBox(height: 16),
              ],
              ...children,
            ],
          ),
        ),
      ],
    );
  }
}
