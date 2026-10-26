import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../money/khr_rate_provider.dart';
import '../../money/money_format.dart';
import '../theme/k_theme.dart';

/// [KPriceSize.lg] for product detail and totals (24/32), [KPriceSize.md] for
/// cards and lines (16/22).
enum KPriceSize { md, lg }

/// A retail price the K way: USD incl. VAT, with the riel equivalent at the
/// settings rate underneath. Never use this for business buyers.
class KPrice extends ConsumerWidget {
  const KPrice({
    super.key,
    required this.cents,
    this.size = KPriceSize.lg,
    this.showKhr = true,
  });

  /// US cents incl. VAT.
  final int cents;
  final KPriceSize size;
  final bool showKhr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final rate = ref.watch(khrRateValueProvider);
    final usdStyle = switch (size) {
      KPriceSize.lg => k.text.price,
      KPriceSize.md => k.text.body.copyWith(
        fontSize: 16,
        height: 22 / 16,
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatUsd(cents), style: usdStyle),
        if (showKhr)
          Text(
            formatKhr(AppLocalizations.of(context), cents, rate: rate),
            style: (size == KPriceSize.lg ? k.text.small : k.text.caption)
                .copyWith(
                  fontWeight: FontWeight.w400,
                  color: k.colors.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
      ],
    );
  }
}
