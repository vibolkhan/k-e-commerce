import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/router/app_role.dart';
import '../../../../core/time/cutoff.dart';
import '../../../../core/time/date_format.dart';
import '../../../../core/time/phnom_penh_time.dart';
import '../../../../core/ui/k_ui.dart';
import '../../../admin/presentation/admin_labels.dart' show durationLabel;
import '../../domain/product_detail.dart';
import '../../domain/storefront.dart';
import '../store_widgets.dart';
import '../storefront_providers.dart';
import 'product_detail_providers.dart';

/// "Colour", "Size", "Pack", or the attribute key in words.
String axisLabel(AppLocalizations l10n, String key) => switch (key) {
  'colour' || 'color' => l10n.pdAxisColour,
  'size' => l10n.pdAxisSize,
  'pack' => l10n.pdAxisPack,
  _ => humaniseKey(key),
};

/// The stock line under the gallery: "In stock" (with "Only N left" when
/// low) or "Out of stock", for the selected variant (CAT-05).
class PdStockLine extends StatelessWidget {
  const PdStockLine({super.key, required this.stock});

  final StockState stock;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: switch (stock) {
        OutOfStock() => [
          KStatusPill(label: l10n.pdOutOfStock, tone: KTone.red, dot: true),
        ],
        InStock() => [
          KStatusPill(label: l10n.storeInStock, tone: KTone.green, dot: true),
        ],
        LowStock(:final left) => [
          KStatusPill(label: l10n.storeInStock, tone: KTone.green, dot: true),
          Text(
            l10n.pdOnlyLeft(left),
            style: k.text.small.copyWith(color: k.colors.muted),
          ),
        ],
      },
    );
  }
}

/// The variant choices: colour swatches on C-05 ([swatches]) or chips with
/// a colour dot on C-05c. Values with nothing in stock are disabled.
class PdOptionPicker extends StatelessWidget {
  const PdOptionPicker({
    super.key,
    required this.selection,
    required this.onChanged,
    this.swatches = true,
  });

  final VariantSelection selection;
  final ValueChanged<VariantSelection> onChanged;

  /// Round swatches for colour (C-05); chips everywhere else.
  final bool swatches;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final axes = selection.product.axes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, axis) in axes.indexed) ...[
          if (i > 0) const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text.rich(
              TextSpan(
                text: swatches
                    ? l10n.pdAxisChosen(axisLabel(l10n, axis.key))
                    : axisLabel(l10n, axis.key),
                style: k.text.label,
                children: [
                  if (swatches)
                    TextSpan(
                      text: selection.valueOf(axis.key) ?? '',
                      style: k.text.label.copyWith(color: k.colors.ink),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: swatches && axis.isColour ? 12 : 8,
            runSpacing: 8,
            children: [
              for (final value in axis.values)
                if (swatches && axis.isColour)
                  _Swatch(
                    value: value,
                    selected: selection.valueOf(axis.key) == value,
                    enabled: selection.isEnabled(axis.key, value),
                    onTap: () => onChanged(selection.select(axis.key, value)),
                  )
                else
                  _OptionChip(
                    value: value,
                    colour: axis.isColour,
                    selected: selection.valueOf(axis.key) == value,
                    enabled: selection.isEnabled(axis.key, value),
                    onTap: () => onChanged(selection.select(axis.key, value)),
                  ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.value,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String value;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: enabled,
      button: true,
      label: enabled ? value : l10n.pdValueSoldOutA11y(value),
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: Tooltip(
        message: enabled ? value : l10n.pdValueSoldOut(value),
        child: InkResponse(
          onTap: enabled ? onTap : null,
          radius: 24,
          child: Container(
            key: ValueKey('swatch-$value'),
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? c.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Opacity(
              opacity: enabled ? 1 : 0.4,
              child: CustomPaint(
                foregroundPainter: enabled ? null : _SlashPainter(c.muted),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(colourSwatch(value)),
                    border: Border.all(color: c.line2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The diagonal line across a sold-out swatch, so it isn't colour alone.
class _SlashPainter extends CustomPainter {
  const _SlashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(size.width * 0.15, size.height * 0.85),
      Offset(size.width * 0.85, size.height * 0.15),
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SlashPainter old) => old.color != color;
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.value,
    required this.colour,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String value;
  final bool colour;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final border = selected ? c.primary : c.line2;
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (colour) ...[
          Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(colourSwatch(value)),
                border: Border.all(color: c.line2),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Text(
          enabled ? value : l10n.pdValueSoldOut(value),
          style: k.text.small.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: enabled ? c.ink : c.muted,
          ),
        ),
      ],
    );
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: enabled,
      button: true,
      label: enabled ? value : l10n.pdValueSoldOutA11y(value),
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: InkWell(
        key: ValueKey('option-$value'),
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(KRadius.input),
        child: CustomPaint(
          painter: enabled ? null : _DashedBorderPainter(c.line2),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: EdgeInsets.symmetric(horizontal: colour ? 12 : 16),
            decoration: BoxDecoration(
              color: selected ? c.tint : c.surface,
              borderRadius: BorderRadius.circular(KRadius.input),
              border: enabled
                  ? Border.all(color: border, width: selected ? 2 : 1)
                  : null,
            ),
            child: Center(widthFactor: 1, child: label),
          ),
        ),
      ),
    );
  }
}

/// The dashed outline of a sold-out option (C-05c).
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(KRadius.input),
        ).deflate(0.5),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

/// The countdown to today's cut-off, ticking every 30 s like the home
/// banner, from the server clock (UTC+7).
mixin CutoffTicker<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  ({SameDayStatus status, StoreClock clock}) sameDayNow() {
    final deviceNow = ref.watch(clockProvider)();
    final clock =
        ref.watch(storeClockProvider).value ?? StoreClock.local(deviceNow);
    return (
      status: SameDayStatus.at(clock.nowFrom(deviceNow), clock),
      clock: clock,
    );
  }
}

/// The delivery card on C-05: when it arrives (live cut-off), returns and
/// payment methods.
class PdDeliveryCard extends ConsumerStatefulWidget {
  const PdDeliveryCard({super.key, required this.product});

  final ProductDetail product;

  @override
  ConsumerState<PdDeliveryCard> createState() => _PdDeliveryCardState();
}

class _PdDeliveryCardState extends ConsumerState<PdDeliveryCard>
    with CutoffTicker {
  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final area = ref.watch(deliverToProvider(watchViewer(ref)))?.area;
    final (:status, :clock) = sameDayNow();
    final end = cutoffLabel(l10n, const Cutoff(deliveryDayEndHour, 0));
    final cutoff = cutoffLabel(l10n, clock.cutoff);
    final (title, line) = switch (status) {
      _ when !widget.product.sameDay => (
        l10n.pdGetItLater,
        area == null ? null : l10n.pdDeliveredTo(area),
      ),
      SameDayOpen(:final remaining) => (
        l10n.pdGetItToday,
        area == null
            ? l10n.pdOrderWithinBy(durationLabel(l10n, remaining), end)
            : l10n.pdOrderWithinByTo(durationLabel(l10n, remaining), end, area),
      ),
      SameDayClosed(:final nextDay, :final isTomorrow) => (
        isTomorrow
            ? l10n.pdGetItTomorrow
            : l10n.pdGetItOn(
                formatShortDate(l10n, nextDay.subtract(phnomPenhOffset)),
              ),
        area == null
            ? l10n.pdCutoffPassed(cutoff)
            : l10n.pdCutoffPassedTo(cutoff, area),
      ),
    };
    final free = widget.product.freeDeliveryCents;
    final detail = [
      if (line != null) '$line.',
      if (free != null && free > 0) l10n.pdFreeOver(formatUsdWhole(free)),
    ].join(' ');
    final body = k.text.small.copyWith(color: c.ink3);
    final strong = k.text.small.copyWith(
      fontWeight: FontWeight.w700,
      color: c.ink,
    );

    Widget row(KIconData icon, Widget child) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KIcon(icon, color: c.primaryInk),
        const SizedBox(width: 12),
        Expanded(child: child),
      ],
    );

    return Container(
      key: const Key('pd-delivery'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.tint,
        border: Border.all(color: c.tintLine),
        borderRadius: BorderRadius.circular(KRadius.card),
      ),
      child: Column(
        children: [
          row(
            KIcons.delivery,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: strong.copyWith(fontSize: 14)),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(detail, style: body),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          row(
            KIcons.returnItem,
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: l10n.pdReturnsTitle(returnWindowDays),
                    style: strong,
                  ),
                  TextSpan(text: l10n.pdReturnsBody),
                ],
              ),
              style: body,
            ),
          ),
          const SizedBox(height: 12),
          row(KIcons.khqr, Text(l10n.pdPayments, style: body)),
        ],
      ),
    );
  }
}

/// The cut-off line in the choose-options sheet (C-05c).
class PdCutoffBanner extends ConsumerStatefulWidget {
  const PdCutoffBanner({super.key});

  @override
  ConsumerState<PdCutoffBanner> createState() => _PdCutoffBannerState();
}

class _PdCutoffBannerState extends ConsumerState<PdCutoffBanner>
    with CutoffTicker {
  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final (:status, :clock) = sameDayNow();
    final bold = k.text.small.copyWith(fontWeight: FontWeight.w800);
    final cutoff = cutoffLabel(l10n, clock.cutoff);
    final InlineSpan span = switch (status) {
      SameDayOpen(:final remaining) => TextSpan(
        children: [
          TextSpan(text: l10n.pdSheetWithinPrefix),
          TextSpan(text: durationLabel(l10n, remaining), style: bold),
          TextSpan(text: l10n.pdSheetWithinSuffix),
        ],
      ),
      SameDayClosed(isTomorrow: true) => TextSpan(
        text: l10n.storeCutoffPassedTomorrow(cutoff),
      ),
      SameDayClosed(:final nextDay) => TextSpan(
        text: l10n.storeCutoffPassedOn(
          formatShortDate(l10n, nextDay.subtract(phnomPenhOffset)),
        ),
      ),
    };
    return KBanner.rich(span: span, icon: KIcons.delivery);
  }
}

/// "You may also like" (C-05): a row of 150 px cards that runs off the edge.
class PdRelatedRow extends StatelessWidget {
  const PdRelatedRow({super.key, required this.product, required this.role});

  final ProductDetail product;
  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (product.related.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KSpacing.gutter),
          child: StoreSectionHead(title: l10n.pdAlsoLike),
        ),
        SizedBox(
          height: 290,
          child: ListView.separated(
            key: const Key('pd-related'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: KSpacing.gutter),
            itemCount: product.related.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(
              width: 150,
              child: StoreProductCard(item: product.related[i], role: role),
            ),
          ),
        ),
      ],
    );
  }
}
