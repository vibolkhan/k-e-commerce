import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_router.dart';
import '../../../core/time/phnom_penh_time.dart';
import '../../../core/ui/k_ui.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/app_notification.dart';
import 'notification_style.dart';
import 'notifications_providers.dart';

/// How long a banner stays (N-03 "Top banners slide in for 5 seconds").
const bannerDuration = Duration(seconds: 5);

/// Older rows arriving (first sync, reconnect) are inbox news, not banners.
const _bannerWindow = Duration(minutes: 2);

/// N-03a: while the app is open, a new notification slides in at the top
/// for 5 seconds; swipe it up to dismiss, tap it (or its action) to open the
/// related screen. It is driven by the live inbox, so it shows whether or
/// not push is set up on this device, and FCM shows nothing in the
/// foreground. Not shown while the inbox itself is open.
class InAppBannerHost extends ConsumerStatefulWidget {
  const InAppBannerHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InAppBannerHost> createState() => _InAppBannerHostState();
}

class _InAppBannerHostState extends ConsumerState<InAppBannerHost> {
  /// Ids already in the inbox; null until the first load for this user.
  Set<String>? _seen;
  AppNotification? _current;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    ref.listenManual(authUserIdProvider, (_, _) {
      _seen = null;
      _hide();
    });
    ref.listenManual(inboxProvider, (_, next) {
      final items = next.value;
      if (items != null) _onInbox(items);
    }, fireImmediately: true);
  }

  void _onInbox(List<AppNotification> items) {
    final seen = _seen;
    _seen = {...?seen, ...items.map((n) => n.id)};
    if (seen == null) return;
    final now = ref.read(clockProvider)();
    final fresh = items.where(
      (n) =>
          !seen.contains(n.id) &&
          n.isUnread &&
          now.difference(n.createdAt) < _bannerWindow,
    );
    if (fresh.isEmpty || _inboxOpen()) return;
    _show(fresh.first);
  }

  bool _inboxOpen() {
    // The top route, including pushed ones.
    return ref.read(routerProvider).state.uri.path.endsWith('/inbox');
  }

  void _show(AppNotification n) {
    _timer?.cancel();
    setState(() => _current = n);
    _timer = Timer(bannerDuration, _hide);
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    if (mounted && _current != null) setState(() => _current = null);
  }

  void _open(AppNotification n) {
    _hide();
    unawaited(markReadQuietly(ref.read(notificationsRepositoryProvider), n.id));
    final route = n.route;
    if (route != null) ref.read(routerProvider).push(route);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 16,
          right: 16,
          top: MediaQuery.paddingOf(context).top + 16,
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween(begin: const Offset(0, -1.4), end: Offset.zero)
                  .animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  ),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: current == null
                ? const SizedBox.shrink()
                : Center(
                    key: ValueKey(current.id),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Dismissible(
                        key: ValueKey('banner-${current.id}'),
                        direction: DismissDirection.up,
                        onDismissed: (_) {
                          _timer?.cancel();
                          setState(() => _current = null);
                        },
                        child: InAppBanner(
                          notification: current,
                          onOpen: () => _open(current),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// The N-03a card: icon tile, title, body and a tonal action.
class InAppBanner extends StatelessWidget {
  const InAppBanner({
    super.key,
    required this.notification,
    required this.onOpen,
  });

  final AppNotification notification;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final n = notification;
    final title = n.titleIn(lang);
    final body = n.bodyIn(lang);
    return Semantics(
      container: true,
      liveRegion: true,
      hint: l10n.notifBannerDismiss,
      child: Material(
        key: const Key('in-app-banner'),
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: n.route == null ? null : onOpen,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.line),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x330F172A),
                  blurRadius: 40,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Row(
              children: [
                NotificationIcon(n.type),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: k.text.body.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: k.text.small.copyWith(
                          fontSize: 14,
                          height: 19 / 14,
                          color: c.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (n.route != null) ...[
                  const SizedBox(width: 8),
                  KButton.tonal(
                    key: const Key('in-app-banner-action'),
                    label: bannerActionLabel(l10n, n.type),
                    size: KButtonSize.sm,
                    onPressed: onOpen,
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
