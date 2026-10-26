import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/domain/statuses.dart';
import 'package:k_e_commerce/core/l10n/generated/app_localizations_en.dart';
import 'package:k_e_commerce/core/l10n/generated/app_localizations_km.dart';
import 'package:k_e_commerce/core/ui/k_ui.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('KTheme', () {
    test('is installed on the app theme', () {
      expect(AppTheme.light().extension<KTheme>(), isNotNull);
      expect(AppTheme.light().colorScheme.primary, KColors.primary);
    });

    test('lerp ends at each side and copyWith replaces fields', () {
      final a = KTheme.light;
      final b = a.copyWith(
        colors: KPalette.lerp(KPalette.light, KPalette.light, 0),
        shadow1: KShadows.level3,
      );
      expect(a.lerp(b, 0).colors, a.colors);
      expect(a.lerp(b, 1).shadow1, KShadows.level3);
      expect(a.lerp(null, .5), same(a));
    });

    test('type scale follows the Brand board', () {
      final t = KTheme.light.text;
      expect(
        [
          t.display,
          t.h1,
          t.h2,
          t.h3,
          t.body,
          t.small,
          t.caption,
        ].map((s) => s.fontSize),
        [32, 24, 20, 17, 15, 13, 12],
      );
      expect(t.body.fontFamily, KFonts.family);
      expect(t.body.fontFamilyFallback, [KFonts.khmer]);
    });
  });

  group('contrast ≥ 4.5:1', () {
    const pairs = {
      'primary on white': (KColors.primary, Colors.white),
      'white on primary': (Colors.white, KColors.primary),
      'ink on bg': (KColors.ink, KColors.bg),
      'muted on white': (KColors.muted, Colors.white),
      'ink3 on soft': (KColors.ink3, KColors.soft),
      'primary ink on sky 100': (KColors.primaryInk, KColors.sky100),
      'ok on ok bg': (KColors.ok, KColors.okBg),
      'warn on warn bg': (KColors.warn, KColors.warnBg),
      'bad on bad bg': (KColors.bad, KColors.badBg),
      'white on danger fill': (Colors.white, KColors.badFill),
      'violet on violet bg': (KColors.violet, KColors.violetBg),
      'sky 300 on ink (toast action)': (KColors.sky300, KColors.ink),
    };
    for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
      test(name, () => expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5)));
    }
  });

  group('status mappings', () {
    final en = AppLocalizationsEn();
    final km = AppLocalizationsKm();

    test('order tones match the Components board', () {
      expect(KStatusPill.orderTone(OrderStatus.pendingPayment), KTone.amber);
      expect(KStatusPill.orderTone(OrderStatus.packing), KTone.blue);
      expect(KStatusPill.orderTone(OrderStatus.outForDelivery), KTone.ink);
      expect(KStatusPill.orderTone(OrderStatus.delivered), KTone.green);
      expect(KStatusPill.orderTone(OrderStatus.failedDelivery), KTone.red);
      expect(KStatusPill.orderTone(OrderStatus.returned), KTone.gray);
    });

    test('payment and quote tones match the Components board', () {
      expect(KStatusPill.paymentTone(PaymentStatus.paid), KTone.green);
      expect(KStatusPill.paymentTone(PaymentStatus.refunded), KTone.violet);
      expect(KStatusPill.paymentTone(PaymentStatus.slipRejected), KTone.red);
      expect(KStatusPill.quoteTone(QuoteStatus.quoteReady), KTone.violet);
      expect(KStatusPill.quoteTone(QuoteStatus.revisionRequested), KTone.amber);
    });

    test('every status has a distinct label in en and km', () {
      for (final l in [en, km]) {
        final order = OrderStatus.values.map(
          (s) => KStatusPill.orderLabel(l, s),
        );
        final pay = PaymentStatus.values.map(
          (s) => KStatusPill.paymentLabel(l, s),
        );
        final quote = QuoteStatus.values.map(
          (s) => KStatusPill.quoteLabel(l, s),
        );
        for (final labels in [order, pay, quote]) {
          expect(labels.every((s) => s.isNotEmpty), isTrue);
          expect(labels.toSet().length, labels.length);
        }
      }
      expect(
        KStatusPill.orderLabel(en, OrderStatus.outForDelivery),
        'Out for delivery',
      );
    });
  });
}
