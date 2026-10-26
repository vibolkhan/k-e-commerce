import 'package:flutter/material.dart';

import '../../domain/statuses.dart';
import '../../l10n/generated/app_localizations.dart';
import '../theme/k_theme.dart';
import '../theme/k_tokens.dart';

enum KTone { blue, green, amber, red, gray, violet, ink, white }

/// Status in words and colour, never colour alone. Named constructors map
/// each status enum exactly as the Components board does.
class KStatusPill extends StatelessWidget {
  const KStatusPill({
    super.key,
    required String this.label,
    required this.tone,
    this.dot = false,
    this.large = false,
  }) : _label = null;

  KStatusPill.order(OrderStatus status, {super.key, this.large = false})
    : tone = orderTone(status),
      dot = true,
      label = null,
      _label = ((l) => orderLabel(l, status));

  KStatusPill.payment(PaymentStatus status, {super.key, this.large = false})
    : tone = paymentTone(status),
      dot = false,
      label = null,
      _label = ((l) => paymentLabel(l, status));

  KStatusPill.quote(QuoteStatus status, {super.key, this.large = false})
    : tone = quoteTone(status),
      dot = true,
      label = null,
      _label = ((l) => quoteLabel(l, status));

  KStatusPill.returns(ReturnStatus status, {super.key, this.large = false})
    : tone = switch (status) {
        ReturnStatus.requested => KTone.amber,
        ReturnStatus.pickupScheduled => KTone.blue,
        ReturnStatus.refunded => KTone.green,
      },
      dot = false,
      label = null,
      _label = ((l) => switch (status) {
        ReturnStatus.requested => l.returnRequested,
        ReturnStatus.pickupScheduled => l.returnPickupScheduled,
        ReturnStatus.refunded => l.returnRefunded,
      });

  KStatusPill.business(
    BusinessVerificationStatus status, {
    super.key,
    this.large = false,
  }) : tone = switch (status) {
         BusinessVerificationStatus.pending => KTone.amber,
         BusinessVerificationStatus.verified => KTone.green,
       },
       dot = false,
       label = null,
       _label = ((l) => switch (status) {
         BusinessVerificationStatus.pending => l.businessPendingVerification,
         BusinessVerificationStatus.verified => l.businessVerified,
       });

  KStatusPill.review(ReviewStatus status, {super.key, this.large = false})
    : tone = switch (status) {
        ReviewStatus.pending => KTone.amber,
        ReviewStatus.hidden => KTone.gray,
      },
      dot = false,
      label = null,
      _label = ((l) => switch (status) {
        ReviewStatus.pending => l.reviewPending,
        ReviewStatus.hidden => l.reviewHidden,
      });

  KStatusPill.riderJob(RiderJobStatus status, {super.key, this.large = false})
    : tone = switch (status) {
        RiderJobStatus.assigned => KTone.blue,
        RiderJobStatus.returnPickup => KTone.violet,
      },
      dot = false,
      label = null,
      _label = ((l) => switch (status) {
        RiderJobStatus.assigned => l.riderJobAssigned,
        RiderJobStatus.returnPickup => l.riderJobReturnPickup,
      });

  final String? label;
  final String Function(AppLocalizations)? _label;
  final KTone tone;

  /// Leading dot — used for lifecycle statuses (order, quote).
  final bool dot;

  /// 28 px instead of 24.
  final bool large;

  static KTone orderTone(OrderStatus s) => switch (s) {
    OrderStatus.pendingPayment || OrderStatus.awaitingBankTransfer => .amber,
    OrderStatus.confirmed || OrderStatus.packing || OrderStatus.ready => .blue,
    OrderStatus.outForDelivery => .ink,
    OrderStatus.delivered => .green,
    OrderStatus.failedDelivery => .red,
    OrderStatus.cancelled || OrderStatus.returned => .gray,
  };

  static String orderLabel(AppLocalizations l, OrderStatus s) => switch (s) {
    OrderStatus.pendingPayment => l.orderPendingPayment,
    OrderStatus.awaitingBankTransfer => l.orderAwaitingBankTransfer,
    OrderStatus.confirmed => l.orderConfirmed,
    OrderStatus.packing => l.orderPacking,
    OrderStatus.ready => l.orderReady,
    OrderStatus.outForDelivery => l.orderOutForDelivery,
    OrderStatus.delivered => l.orderDelivered,
    OrderStatus.failedDelivery => l.orderFailedDelivery,
    OrderStatus.cancelled => l.orderCancelled,
    OrderStatus.returned => l.orderReturned,
  };

  static KTone paymentTone(PaymentStatus s) => switch (s) {
    PaymentStatus.paid => .green,
    PaymentStatus.waitingForKhqr ||
    PaymentStatus.awaitingConfirmation => .amber,
    PaymentStatus.cashOnDelivery || PaymentStatus.expired => .gray,
    PaymentStatus.slipRejected => .red,
    PaymentStatus.refunded => .violet,
  };

  static String paymentLabel(AppLocalizations l, PaymentStatus s) =>
      switch (s) {
        PaymentStatus.paid => l.paymentPaid,
        PaymentStatus.waitingForKhqr => l.paymentWaitingForKhqr,
        PaymentStatus.awaitingConfirmation => l.paymentAwaitingConfirmation,
        PaymentStatus.cashOnDelivery => l.paymentCashOnDelivery,
        PaymentStatus.expired => l.paymentExpired,
        PaymentStatus.slipRejected => l.paymentSlipRejected,
        PaymentStatus.refunded => l.paymentRefunded,
      };

  static KTone quoteTone(QuoteStatus s) => switch (s) {
    QuoteStatus.submitted || QuoteStatus.expired => .gray,
    QuoteStatus.inReview => .blue,
    QuoteStatus.quoteReady => .violet,
    QuoteStatus.revisionRequested => .amber,
    QuoteStatus.accepted => .green,
    QuoteStatus.rejected => .red,
  };

  static String quoteLabel(AppLocalizations l, QuoteStatus s) => switch (s) {
    QuoteStatus.submitted => l.quoteSubmitted,
    QuoteStatus.inReview => l.quoteInReview,
    QuoteStatus.quoteReady => l.quoteReady,
    QuoteStatus.revisionRequested => l.quoteRevisionRequested,
    QuoteStatus.accepted => l.quoteAccepted,
    QuoteStatus.rejected => l.quoteRejected,
    QuoteStatus.expired => l.quoteExpired,
  };

  /// Background and text colour for a tone.
  static (Color, Color) colorsFor(KPalette c, KTone tone) => switch (tone) {
    KTone.blue => (c.tint2, c.primaryInk),
    KTone.green => (c.okBg, c.ok),
    KTone.amber => (c.warnBg, c.warn),
    KTone.red => (c.badBg, c.bad),
    KTone.gray => (c.soft, c.ink3),
    KTone.violet => (c.violetBg, c.violet),
    KTone.ink => (c.ink, Colors.white),
    KTone.white => (Colors.white, c.primaryInk),
  };

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final (bg, fg) = colorsFor(k.colors, tone);
    final text = label ?? _label!(AppLocalizations.of(context));
    return Container(
      height: large ? 28 : 24,
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(KRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            maxLines: 1,
            style: k.text.caption.copyWith(
              fontSize: large ? 13 : 12,
              height: 1,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
