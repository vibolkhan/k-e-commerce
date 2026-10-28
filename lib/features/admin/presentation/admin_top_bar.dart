import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/time/cutoff.dart';
import '../../../core/time/phnom_penh_time.dart';
import '../../../core/ui/k_ui.dart';
import '../../account/presentation/account_actions.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../../settings/presentation/language_sheet.dart';
import 'admin_labels.dart';
import 'admin_providers.dart';

/// CmpAdminTopbar: search ("/" focuses it), the same-day cut-off countdown,
/// help, notifications and the account menu.
class AdminTopBar extends ConsumerWidget {
  const AdminTopBar({super.key, required this.searchFocus});

  final FocusNode searchFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.k.colors;
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Semantics(
                  label: l10n.adminSearchLabel,
                  textField: true,
                  child: KTextField.search(
                    key: const Key('admin-search'),
                    hint: l10n.adminSearchHint,
                    focusNode: searchFocus,
                    // Global search lands with its own task.
                    onSubmitted: (_) => showComingSoon(context),
                    suffix: const _KeyHint('/'),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          const CutoffPill(),
          const SizedBox(width: 8),
          KIconButton(
            icon: KIcons.help,
            label: l10n.adminHelp,
            onPressed: () => showComingSoon(context),
          ),
          const NotificationBell(shell: AppRoutes.admin),
          const SizedBox(width: 8),
          const AdminAccountMenu(),
        ],
      ),
    );
  }
}

/// The keyboard shortcut shown inside the search box.
class _KeyHint extends StatelessWidget {
  const _KeyHint(this.shortcut);

  final String shortcut;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: k.colors.surface,
          border: Border.all(color: k.colors.line2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          shortcut,
          style: k.text.caption.copyWith(color: k.colors.ink3),
        ),
      ),
    );
  }
}

/// "Same-day cut-off in 4h 35m" (amber), or that today's cut-off has
/// passed. Display only: the server decides the delivery day.
class CutoffPill extends ConsumerStatefulWidget {
  const CutoffPill({super.key});

  @override
  ConsumerState<CutoffPill> createState() => _CutoffPillState();
}

class _CutoffPillState extends ConsumerState<CutoffPill> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final now = ref.watch(clockProvider)();
    final cutoff = ref.watch(cutoffProvider).value ?? Cutoff.standard;
    final left = cutoff.remaining(now);
    final (bg, fg) = KStatusPill.colorsFor(
      k.colors,
      left == null ? KTone.gray : KTone.amber,
    );
    final text = left == null
        ? l10n.adminCutoffPassed
        : l10n.adminCutoffIn(durationLabel(l10n, left));
    return Container(
      key: const Key('cutoff-pill'),
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(KRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KIcon(KIcons.time, size: 16, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: k.text.caption.copyWith(
                fontSize: 13,
                height: 1,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Initials, name and role; opens Language and Sign out.
class AdminAccountMenu extends ConsumerWidget {
  const AdminAccountMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(currentProfileProvider).value;
    final role = ref.watch(currentStaffRoleProvider);
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        MenuItemButton(
          key: const Key('admin-menu-language'),
          leadingIcon: const KIcon(KIcons.language, size: 20),
          onPressed: () => showLanguageSheet(context),
          child: Text(l10n.languageTitle),
        ),
        if (profile != null)
          MenuItemButton(
            key: const Key('admin-menu-sign-out'),
            leadingIcon: const KIcon(KIcons.back, size: 20),
            onPressed: () => confirmSignOut(context, ref),
            child: Text(l10n.authSignOut),
          ),
      ],
      builder: (context, controller, _) => Semantics(
        button: true,
        label: l10n.adminAccountMenu,
        child: InkWell(
          key: const Key('admin-account-menu'),
          borderRadius: BorderRadius.circular(12),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                KAvatar(initialsOf(profile?.fullName), size: KAvatarSize.sm),
                const SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.fullName ?? l10n.roleAdmin,
                      style: k.text.label.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (role != null)
                      Text(
                        staffRoleLabel(l10n, role),
                        style: k.text.caption.copyWith(color: k.colors.muted),
                      ),
                  ],
                ),
                const SizedBox(width: 6),
                KIcon(KIcons.chevronDown, size: 18, color: k.colors.ink3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
