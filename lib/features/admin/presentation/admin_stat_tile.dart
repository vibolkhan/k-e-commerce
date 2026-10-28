import 'package:flutter/widgets.dart';

import '../../../core/ui/k_ui.dart';

/// A k-ui `.kpi` tile: muted label, big tabular number, muted footnote.
/// Used for summary rows across back-office pages (A-06).
class AdminStatTile extends StatelessWidget {
  const AdminStatTile({
    super.key,
    required this.label,
    required this.value,
    this.footnote,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? footnote;

  /// Amber or red when the number needs attention.
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Semantics(
      container: true,
      label: [label, value, ?footnote].join(', '),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: k.colors.surface,
          border: Border.all(color: k.colors.line),
          borderRadius: BorderRadius.circular(KRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: k.text.small.copyWith(
                color: k.colors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: k.text.h1.copyWith(
                fontSize: 28,
                height: 36 / 28,
                fontWeight: FontWeight.w800,
                color: valueColor ?? k.colors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (footnote != null) ...[
              const SizedBox(height: 2),
              Text(
                footnote!,
                style: k.text.caption.copyWith(color: k.colors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lays tiles out four across on desktop, two across on phones.
class AdminStatRow extends StatelessWidget {
  const AdminStatRow({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final across = constraints.maxWidth >= 840 ? 4 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (across - 1)) / across;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}
