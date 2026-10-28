import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import 'inventory_labels.dart';
import 'inventory_providers.dart';

/// "View adjustment history" (A-06): every stock movement, newest first,
/// with who made it or the order behind it.
Future<void> showStockHistory(BuildContext context) => showKBottomSheet<void>(
  context,
  title: AppLocalizations.of(context).inventoryHistoryTitle,
  builder: (_) => const StockHistoryList(),
);

class StockHistoryList extends ConsumerWidget {
  const StockHistoryList({super.key, this.variantId});

  final String? variantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final history = ref.watch(stockHistoryProvider(variantId));
    return switch (history) {
      AsyncValue(:final value?) when value.isEmpty => Text(
        l10n.inventoryHistoryEmpty,
        style: k.text.small.copyWith(color: k.colors.muted),
      ),
      AsyncValue(:final value?) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: value.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: k.colors.line),
          itemBuilder: (context, i) {
            final m = value[i];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.label,
                          style: k.text.label.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            m.sku,
                            changeLabel(l10n, m.reason, m.delta),
                            if (m.note != null) m.note!,
                          ].join(' · '),
                          style: k.text.small,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    whoLabel(
                      l10n,
                      at: m.at,
                      actor: m.actor,
                      orderNumber: m.orderNumber,
                    ),
                    style: k.text.caption.copyWith(color: k.colors.muted),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      AsyncValue(hasError: true) => Text(
        l10n.inventoryHistoryFailed,
        style: k.text.small.copyWith(color: k.colors.bad),
      ),
      _ => const Center(child: KSpinner()),
    };
  }
}
