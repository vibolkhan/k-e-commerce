import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/ui/k_ui.dart';
import 'notifications_providers.dart';

/// Header bell (C-01, B-00, S-08): opens S-07, red dot while anything is
/// unread (N-03 "Badges on navigation").
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, required this.shell});

  /// `/customer` or `/business`.
  final String shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return KIconButton(
      key: const Key('notification-bell'),
      icon: KIcons.notifications,
      label: AppLocalizations.of(context).notifBell(unread),
      style: KIconButtonStyle.soft,
      dot: unread > 0,
      onPressed: () => context.push(AppRoutes.inbox(shell)),
    );
  }
}
