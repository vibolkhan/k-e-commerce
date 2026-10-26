import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/time/phnom_penh_time.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/app_notification.dart';
import 'notification_style.dart';
import 'notifications_providers.dart';

/// S-07 Notification inbox: tabs All / Orders / Quotes / Chat, Today and
/// Earlier, unread rows bold with a blue dot. A tap marks the row read and
/// opens the related screen (N-03 "Inbox rows").
class InboxPage extends ConsumerStatefulWidget {
  const InboxPage({super.key, required this.shell});

  /// `/customer` or `/business`; back goes here when there is nothing to pop
  /// (opened from a push).
  final String shell;

  @override
  ConsumerState<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends ConsumerState<InboxPage> {
  InboxTab _tab = InboxTab.all;

  Future<void> _markAllRead() async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(notificationsRepositoryProvider).markAllRead();
    } catch (_) {
      if (mounted) {
        showKToast(
          context,
          message: l10n.notifMarkAllFailed,
          tone: KToastTone.bad,
        );
      }
    }
  }

  void _open(AppNotification n) {
    if (n.isUnread) {
      unawaited(
        markReadQuietly(ref.read(notificationsRepositoryProvider), n.id),
      );
    }
    final route = n.route;
    if (route != null) context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inbox = ref.watch(inboxProvider);
    final items = inbox.value ?? const <AppNotification>[];
    final unread = items.where((n) => n.isUnread).length;
    String label(InboxTab tab) => switch (tab) {
      InboxTab.all => l10n.notifTabAll,
      InboxTab.orders => l10n.notifTabOrders,
      InboxTab.quotes => l10n.notifTabQuotes,
      InboxTab.chat => l10n.notifTabChat,
    };

    return Scaffold(
      appBar: KAppBar(
        title: l10n.notifTitle,
        centerTitle: false,
        showBack: true,
        onBack: () =>
            context.canPop() ? context.pop() : context.go(widget.shell),
        actions: [
          KButton.ghost(
            key: const Key('inbox-mark-all'),
            label: l10n.notifMarkAllRead,
            size: KButtonSize.sm,
            onPressed: unread == 0 ? null : _markAllRead,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: l10n.notifTabsLabel,
            container: true,
            child: KTabs(
              fill: true,
              selectedIndex: _tab.index,
              onChanged: (i) => setState(() => _tab = InboxTab.values[i]),
              tabs: [
                for (final tab in InboxTab.values)
                  KTab(
                    label(tab),
                    count: tab == InboxTab.all && unread > 0 ? unread : null,
                  ),
              ],
            ),
          ),
          Expanded(
            child: switch (inbox) {
              AsyncError() when items.isEmpty => _LoadFailed(
                onRetry: () => ref.invalidate(inboxProvider),
              ),
              AsyncLoading() when items.isEmpty => const Center(
                child: KSpinner(size: 24, blue: true),
              ),
              _ => _InboxList(
                items: items.where(_tab.shows).toList(),
                onOpen: _open,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _InboxList extends ConsumerWidget {
  const _InboxList({required this.items, required this.onOpen});

  final List<AppNotification> items;
  final ValueChanged<AppNotification> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (items.isEmpty) {
      return ListView(
        children: [
          KEmptyState(
            icon: KIcons.notifications,
            title: l10n.notifEmptyTitle,
            message: l10n.notifEmptyBody,
          ),
        ],
      );
    }
    final now = ref.watch(clockProvider)();
    final groups = groupByDay(items, now: now);
    Widget group(String title, List<AppNotification> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Semantics(header: true, child: KOverline(title)),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: context.k.colors.line),
            ),
          ),
          child: KList(
            children: [
              for (final n in rows)
                _InboxRow(n, now: now, onTap: () => onOpen(n)),
            ],
          ),
        ),
      ],
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (groups.today.isNotEmpty) group(l10n.notifToday, groups.today),
        if (groups.earlier.isNotEmpty) group(l10n.notifEarlier, groups.earlier),
      ],
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow(this.n, {required this.now, required this.onTap});

  final AppNotification n;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final unread = n.isUnread;
    final time = inboxTimeLabel(l10n, n.createdAt, now: now);
    final title = n.titleIn(lang);
    final body = n.bodyIn(lang);
    return Semantics(
      button: n.route != null,
      label: [if (unread) l10n.notifUnread, title, body, time].join(', '),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: c.surface,
        child: InkWell(
          key: Key('inbox-row-${n.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NotificationIcon(n.type),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: k.text.body.copyWith(
                          fontWeight: unread
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: k.text.small.copyWith(
                          height: 18 / 13,
                          color: unread ? c.ink2 : c.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        time,
                        style: k.text.caption.copyWith(
                          color: c.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unread) ...[
                  const SizedBox(width: 12),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: KDot(key: Key('inbox-unread-dot')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        KBanner(message: l10n.notifLoadFailed, tone: KBannerTone.bad),
        const SizedBox(height: 12),
        Center(
          child: KButton.outline(
            label: l10n.notifRetry,
            size: KButtonSize.sm,
            onPressed: onRetry,
          ),
        ),
      ],
    );
  }
}
