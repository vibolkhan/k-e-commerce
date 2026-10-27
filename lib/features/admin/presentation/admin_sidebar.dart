import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/admin_section.dart';
import '../domain/staff_permissions.dart';
import 'admin_labels.dart';
import 'admin_providers.dart';

/// CmpAdminSidebar: K Admin, the store, then the sections this staff role
/// can open, grouped, with their waiting counts.
class AdminSidebar extends ConsumerWidget {
  const AdminSidebar({super.key, required this.current});

  /// The open section, highlighted.
  final AdminSection? current;

  static const width = 248.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final role = ref.watch(currentStaffRoleProvider);
    final badges = ref.watch(adminBadgesProvider).value ?? const {};
    final sections = role == null ? const <AdminSection>[] : sectionsFor(role);

    final children = <Widget>[];
    AdminGroup? group;
    for (final section in sections) {
      if (section.group != null && section.group != group) {
        group = section.group;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
            child: Semantics(
              header: true,
              child: KOverline(groupLabel(l10n, group!)),
            ),
          ),
        );
      }
      children.add(
        AdminNavLink(
          section: section,
          selected: section == current,
          badge: badges[section],
          onTap: () => context.go(section.path),
        ),
      );
    }

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.line)),
      ),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: l10n.adminNavLabel,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: const KAppIcon(size: 36),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.adminTitle,
                          style: k.text.title.copyWith(
                            fontSize: 16,
                            height: 20 / 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          l10n.adminStoreName,
                          style: k.text.caption.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// One 44 px sidebar (or M-05 list) entry.
class AdminNavLink extends StatelessWidget {
  const AdminNavLink({
    super.key,
    required this.section,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final AdminSection section;
  final bool selected;
  final int? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final label = sectionLabel(l10n, section);
    final count = badge ?? 0;
    final color = selected ? c.primaryInk : c.ink2;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: count > 0 ? l10n.uiBadgeCount(label, count) : label,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.tint2 : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: Key('admin-nav-${section.name}'),
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  KIcon(sectionIcon(section), size: 20, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: k.text.label.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                  if (count > 0)
                    KBadge(count, blue: sectionBadgeBlue(section), ring: false),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
