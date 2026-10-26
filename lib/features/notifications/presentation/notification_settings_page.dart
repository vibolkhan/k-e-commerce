import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/bootstrap.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_role.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/notification_prefs.dart';
import 'notifications_providers.dart';

/// S-08d Notification settings: Push (and Email) per kind of message.
/// Payment and security messages ignore these (banner at the bottom), and
/// everything still lands in the inbox. Quotes are for business buyers only.
class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key, required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(appConfigProvider);
    final prefs = ref.watch(notificationPrefsProvider);
    final c = context.k.colors;

    Future<void> set(
      NotificationGroup group,
      NotificationChannel channel,
      bool value,
    ) async {
      final saved = await ref
          .read(notificationPrefsProvider.notifier)
          .set(group, channel, value);
      if (!saved && context.mounted) {
        showKToast(
          context,
          message: l10n.notifSettingsSaveFailed,
          tone: KToastTone.bad,
        );
      }
    }

    final cards = [
      (
        NotificationGroup.orders,
        KIcons.delivery,
        c.tint2,
        c.primaryInk,
        l10n.notifSettingsOrdersTitle,
        l10n.notifSettingsOrdersBody,
      ),
      if (role == AppRole.business)
        (
          NotificationGroup.quotes,
          KIcons.quote,
          c.violetBg,
          c.violet,
          l10n.notifSettingsQuotesTitle,
          l10n.notifSettingsQuotesBody,
        ),
      (
        NotificationGroup.chat,
        KIcons.chat,
        c.okBg,
        c.ok,
        l10n.notifSettingsChatTitle,
        l10n.notifSettingsChatBody,
      ),
      (
        NotificationGroup.reviews,
        KIcons.star,
        c.warnBg,
        c.warn,
        l10n.notifSettingsReviewsTitle,
        l10n.notifSettingsReviewsBody,
      ),
    ];

    return Scaffold(
      appBar: KAppBar(title: l10n.notifTitle, line: true),
      body: switch (prefs) {
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final (group, icon, bg, fg, title, body) in cards) ...[
              _GroupCard(
                key: Key('notif-group-${group.name}'),
                icon: icon,
                iconBg: bg,
                iconColor: fg,
                title: title,
                description: body,
                switches: [
                  _SwitchLine(
                    key: Key('notif-${group.name}-push'),
                    label: l10n.notifSettingsPush,
                    value: value.isOn(group, NotificationChannel.push),
                    onChanged: (v) => set(group, NotificationChannel.push, v),
                  ),
                  if (group.email)
                    _SwitchLine(
                      key: Key('notif-${group.name}-email'),
                      label: l10n.notifSettingsEmail,
                      value: value.isOn(group, NotificationChannel.email),
                      onChanged: (v) =>
                          set(group, NotificationChannel.email, v),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            KBanner(message: l10n.notifSettingsAlwaysOn),
            if (!config.isProd) ...[
              const SizedBox(height: 24),
              _TestPush(role: role),
            ],
          ],
        ),
        AsyncError() => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              KBanner(message: l10n.notifLoadFailed, tone: KBannerTone.bad),
              const SizedBox(height: 12),
              KButton.outline(
                label: l10n.notifRetry,
                size: KButtonSize.sm,
                onPressed: () => ref.invalidate(notificationPrefsProvider),
              ),
            ],
          ),
        ),
        _ => const Center(child: KSpinner(size: 24, blue: true)),
      },
    );
  }
}

/// Card with an icon tile, title and one-line description, then switches.
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.switches,
  });

  final KIconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String description;
  final List<Widget> switches;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    return KCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(KRadius.input),
                  ),
                  alignment: Alignment.center,
                  child: KIcon(icon, size: 20, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: k.text.body.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        description,
                        style: k.text.small.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final s in switches)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: s,
            ),
        ],
      ),
    );
  }
}

class _SwitchLine extends StatelessWidget {
  const _SwitchLine({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  // The whole row toggles, not just the switch.
  @override
  Widget build(BuildContext context) => Material(
    color: context.k.colors.surface,
    child: InkWell(
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: KSwitchRow(label: label, value: value, onChanged: onChanged),
        ),
      ),
    ),
  );
}

/// Dev and staging: sends this account a test push that opens a chosen
/// screen, for the F07 "a test push opens the right screen" check.
class _TestPush extends ConsumerStatefulWidget {
  const _TestPush({required this.role});

  final AppRole role;

  @override
  ConsumerState<_TestPush> createState() => _TestPushState();
}

class _TestPushState extends ConsumerState<_TestPush> {
  // Seeded rows (supabase/seed.sql) the targets open.
  static const _targets = {
    'inbox': null,
    'order': 'd0000000-0000-4000-8000-000000010248',
    'chat': '91000000-0000-4000-8000-000000000001',
    'quote': 'b0000000-0000-4000-8000-000000000312',
  };

  String _target = 'inbox';
  bool _busy = false;

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(notificationsRepositoryProvider)
          .sendTest(
            target: _target,
            id: _targets[_target],
            delay: const Duration(seconds: 10),
          );
      if (mounted) showKToast(context, message: l10n.notifTestSent);
    } catch (_) {
      if (mounted) {
        showKToast(
          context,
          message: l10n.notifTestFailed,
          tone: KToastTone.bad,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    String name(String target) => switch (target) {
      'order' => l10n.notifTestTargetOrder,
      'chat' => l10n.notifTestTargetChat,
      'quote' => l10n.notifTestTargetQuote,
      _ => l10n.notifTestTargetInbox,
    };
    return KCard(
      style: KCardStyle.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.notifTestTitle,
            style: k.text.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.notifTestBody,
            style: k.text.small.copyWith(color: k.colors.muted),
          ),
          const SizedBox(height: 12),
          Text(l10n.notifTestTarget, style: k.text.label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final target in _targets.keys)
                // Quotes live in the business shell only.
                if (target != 'quote' || widget.role == AppRole.business)
                  KChip(
                    label: name(target),
                    selected: target == _target,
                    onTap: () => setState(() => _target = target),
                  ),
            ],
          ),
          const SizedBox(height: 12),
          KButton.outline(
            key: const Key('notif-test-send'),
            label: l10n.notifTestSend,
            icon: KIcons.notifications,
            loading: _busy,
            onPressed: _busy ? null : _send,
          ),
        ],
      ),
    );
  }
}
