import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/time/phnom_penh_time.dart';
import '../../../core/ui/k_ui.dart';
import '../../account/presentation/account_actions.dart';
import '../domain/admin_section.dart';
import '../domain/staff_member.dart';
import '../domain/staff_permissions.dart';
import '../domain/staff_role.dart';
import 'admin_labels.dart';
import 'admin_pages.dart';
import 'admin_providers.dart';
import 'admin_shell.dart';
import 'staff_dialogs.dart';

/// A-14d Settings · Staff & roles: who is on the staff, what each role may
/// do, and the way in to A-14e (invite) and the edit dialog.
class StaffRolesPage extends ConsumerWidget {
  const StaffRolesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final wide = isAdminWide(context);
    const panels = [_StaffPanel(), SizedBox(height: 24), _MatrixPanel()];
    return AdminPage(
      title: l10n.adminSettingsStaff,
      showBack: true,
      parent: AdminSection.settings.path,
      children: [
        if (wide)
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsNav(current: SettingsPage.staff),
              SizedBox(width: 24),
              Expanded(child: Column(children: panels)),
            ],
          )
        else
          ...panels,
      ],
    );
  }
}

/// White 16 px-radius panel with a header row (k-ui `.panel`).
class _Panel extends StatelessWidget {
  const _Panel({required this.head, required this.child, this.headTrailing});

  final Widget head;
  final Widget? headTrailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(KRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                Expanded(child: head),
                if (headTrailing != null) ...[
                  const SizedBox(width: 12),
                  headTrailing!,
                ],
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: k.text.title.copyWith(
              fontSize: 16,
              height: 22 / 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: k.text.caption.copyWith(color: k.colors.muted),
          ),
      ],
    );
  }
}

class _StaffPanel extends ConsumerWidget {
  const _StaffPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final staff = ref.watch(staffDirectoryProvider);
    final now = ref.watch(clockProvider)();
    final members = staff.value ?? const <StaffMember>[];
    final Widget body;
    if (staff.hasError && !staff.hasValue) {
      body = Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            KBanner(message: l10n.staffLoadFailed, tone: KBannerTone.bad),
            const SizedBox(height: 12),
            KButton.outline(
              label: l10n.staffRetry,
              onPressed: () => ref.invalidate(staffDirectoryProvider),
            ),
          ],
        ),
      );
    } else if (!staff.hasValue) {
      body = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: KSpinner(blue: true)),
      );
    } else if (isAdminWide(context)) {
      body = _StaffTable(members: members, now: now);
    } else {
      body = Column(
        children: [
          for (final member in members) _StaffCard(member: member, now: now),
        ],
      );
    }
    return _Panel(
      head: _PanelTitle(l10n.staffCount(members.length)),
      headTrailing: KButton(
        key: const Key('invite-staff'),
        label: l10n.staffInvite,
        icon: KIcons.plus,
        size: KButtonSize.sm,
        onPressed: () => showInviteStaffDialog(context),
      ),
      child: body,
    );
  }
}

/// Pending invites get Resend; everyone else Edit (not for yourself).
class _MemberAction extends ConsumerWidget {
  const _MemberAction({required this.member});

  final StaffMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (member.isPending) {
      return KButton.outline(
        key: Key('resend-${member.id}'),
        label: l10n.staffResend,
        size: KButtonSize.sm,
        onPressed: () => resendInvite(context, ref, member),
      );
    }
    return KButton.outline(
      key: Key('edit-${member.id}'),
      label: l10n.staffEdit,
      size: KButtonSize.sm,
      onPressed: member.isMe
          ? null
          : () => showEditStaffDialog(context, member),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.member, required this.now});

  final StaffMember member;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (member.isExpired(now)) {
      return KStatusPill(label: l10n.staffExpired, tone: KTone.red, dot: true);
    }
    return member.status == StaffStatus.active
        ? KStatusPill(label: l10n.staffActive, tone: KTone.green, dot: true)
        : KStatusPill(label: l10n.staffPending, tone: KTone.amber, dot: true);
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.member});

  final StaffMember member;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final contact = member.isMe
        ? '${staffContactLabel(member)} · ${l10n.staffYou}'
        : staffContactLabel(member);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KAvatar(
          initialsOf(member.fullName),
          size: KAvatarSize.sm,
          tone: member.isPending ? KAvatarTone.grey : KAvatarTone.sky,
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                member.fullName ?? staffContactLabel(member),
                style: k.text.label.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                contact,
                style: k.text.caption.copyWith(color: k.colors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Desktop: Name · Role · Last active · Status · Actions.
class _StaffTable extends StatelessWidget {
  const _StaffTable({required this.members, required this.now});

  final List<StaffMember> members;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    Widget head(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Text(
        text.toUpperCase(),
        style: k.text.caption.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: c.ink3,
        ),
      ),
    );
    Widget cell(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
    final body = k.text.body.copyWith(fontSize: 14);
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.4),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(),
        4: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: c.bg,
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          children: [
            head(l10n.staffColName),
            head(l10n.staffColRole),
            head(l10n.staffColLastActive),
            head(l10n.staffColStatus),
            head(l10n.staffColActions),
          ],
        ),
        for (final (i, member) in members.indexed)
          TableRow(
            key: ValueKey('staff-row-${member.id}'),
            decoration: i == members.length - 1
                ? null
                : BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.line)),
                  ),
            children: [
              cell(_NameCell(member: member)),
              cell(Text(staffRoleLabel(l10n, member.role), style: body)),
              cell(Text(lastActiveLabel(l10n, member, now: now), style: body)),
              cell(_StatusPill(member: member, now: now)),
              cell(_MemberAction(member: member)),
            ],
          ),
      ],
    );
  }
}

/// Phone: one card per member.
class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.member, required this.now});

  final StaffMember member;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    return Container(
      key: ValueKey('staff-row-${member.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: k.colors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _NameCell(member: member)),
              _StatusPill(member: member, now: now),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${staffRoleLabel(l10n, member.role)} · '
                  '${lastActiveLabel(l10n, member, now: now)}',
                  style: k.text.small.copyWith(color: k.colors.ink3),
                ),
              ),
              _MemberAction(member: member),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Roles & permissions" — read from [staffMatrix], the same table the menu
/// and router use.
class _MatrixPanel extends StatelessWidget {
  const _MatrixPanel();

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    Widget headCell(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Text(
        text.toUpperCase(),
        style: k.text.caption.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: c.ink3,
        ),
      ),
    );
    Widget accessCell(AreaAccess access) {
      final label = accessLabel(l10n, access);
      final none = access.level == AccessLevel.none;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Semantics(
          label: label,
          excludeSemantics: true,
          child: Text(
            none ? '—' : label,
            style: k.text.body.copyWith(
              fontSize: 14,
              fontWeight: access.level == AccessLevel.full
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: none
                  ? c.muted
                  : access.level == AccessLevel.full
                  ? c.ink
                  : c.primaryInk,
            ),
          ),
        ),
      );
    }

    final table = Table(
      key: const Key('permission-matrix'),
      columnWidths: const {0: FlexColumnWidth(1.6)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: c.bg,
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          children: [
            headCell(l10n.staffMatrixArea),
            for (final role in StaffRole.values)
              headCell(staffRoleLabel(l10n, role)),
          ],
        ),
        for (final area in PermissionArea.values)
          TableRow(
            decoration: area == PermissionArea.values.last
                ? null
                : BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.line)),
                  ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                child: Text(
                  areaLabel(l10n, area),
                  style: k.text.label.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              for (final role in StaffRole.values)
                accessCell(accessFor(role, area)),
            ],
          ),
      ],
    );

    return _Panel(
      head: _PanelTitle(
        l10n.staffMatrixTitle,
        subtitle: l10n.staffMatrixSubtitle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // Scrolls sideways on phones rather than squeezing the cells.
              child: SizedBox(
                width: constraints.maxWidth < 640 ? 640 : constraints.maxWidth,
                child: table,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: c.bg,
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                KIcon(KIcons.lock, size: 16, color: c.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.staffServerNote,
                    style: k.text.small.copyWith(color: c.ink3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
