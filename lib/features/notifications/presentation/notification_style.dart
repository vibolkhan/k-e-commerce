import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/time/date_format.dart';
import '../../../core/time/phnom_penh_time.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/app_notification.dart';

/// 40 px tinted icon tile for a notification type (S-07 rows, N-03a banner).
class NotificationIcon extends StatelessWidget {
  const NotificationIcon(this.type, {super.key});

  final String type;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    final (icon, bg, fg) = switch (type) {
      'chat_message' || 'admin_chat_waiting' => (KIcons.chat, c.okBg, c.ok),
      'order_out_for_delivery' ||
      'job_assigned' ||
      'return_pickup_assigned' ||
      'job_reassigned' => (KIcons.delivery, c.tint2, c.primaryInk),
      'payment_received' ||
      'bank_transfer_confirmed' ||
      'order_confirmed_cod' ||
      'refund_sent' ||
      'business_approved' => (KIcons.success, c.okBg, c.ok),
      'payment_expired' ||
      'delivery_failed' ||
      'bank_slip_rejected' ||
      'business_rejected' ||
      'admin_delivery_failed' => (KIcons.alert, c.badBg, c.bad),
      'return_approved' ||
      'return_rejected' ||
      'admin_return_requested' => (KIcons.returnItem, c.warnBg, c.warn),
      'review_reminder' => (KIcons.star, c.warnBg, c.warn),
      'quote_ready' ||
      'quote_revised' ||
      'quote_expiring' ||
      'admin_new_rfq' => (KIcons.quote, c.violetBg, c.violet),
      'test' => (KIcons.notifications, c.tint, c.primaryInk),
      _ => (KIcons.package, c.soft, c.ink2),
    };
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(KRadius.input),
        ),
        alignment: Alignment.center,
        child: KIcon(icon, size: 20, color: fg),
      ),
    );
  }
}

/// N-03a action: "Track" for a delivery on its way, otherwise "View".
String bannerActionLabel(AppLocalizations l10n, String type) =>
    type == 'order_out_for_delivery'
    ? l10n.notifBannerTrack
    : l10n.notifBannerView;

/// S-07 time: "1:50 PM" today, "Yesterday", then "21 Oct" (Phnom Penh).
String inboxTimeLabel(
  AppLocalizations l10n,
  DateTime instant, {
  required DateTime now,
}) => switch (phnomPenhDaysBetween(instant, now)) {
  0 => formatTime(l10n, instant),
  1 => l10n.dateYesterday,
  _ => DateFormat('d MMM', l10n.localeName).format(toPhnomPenh(instant)),
};

/// S-07 groups: Today (Phnom Penh day of [now]) and Earlier.
({List<AppNotification> today, List<AppNotification> earlier}) groupByDay(
  Iterable<AppNotification> items, {
  required DateTime now,
}) {
  final today = <AppNotification>[];
  final earlier = <AppNotification>[];
  for (final n in items) {
    (phnomPenhDaysBetween(n.createdAt, now) <= 0 ? today : earlier).add(n);
  }
  return (today: today, earlier: earlier);
}
