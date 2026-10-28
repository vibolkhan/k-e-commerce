import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog_list.dart';

/// A-05e: confirm before archiving one product, with what it touches.
/// True when the staff member confirmed.
Future<bool> confirmArchive(
  BuildContext context, {
  required String productId,
  required String name,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: KColors.scrim,
    builder: (_) => ArchiveDialog(productId: productId, name: name),
  );
  return confirmed ?? false;
}

class ArchiveDialog extends ConsumerStatefulWidget {
  const ArchiveDialog({super.key, required this.productId, required this.name});

  final String productId;
  final String name;

  @override
  ConsumerState<ArchiveDialog> createState() => _ArchiveDialogState();
}

class _ArchiveDialogState extends ConsumerState<ArchiveDialog> {
  late final Future<ArchiveImpact> _impact = ref
      .read(catalogRepositoryProvider)
      .archiveImpact(widget.productId)
      .catchError((Object _) => const ArchiveImpact());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: k.colors.surface,
            borderRadius: BorderRadius.circular(KRadius.dialog),
          ),
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: l10n.catalogArchiveTitle(widget.name),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: k.colors.badBg,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: KIcon(KIcons.delete, color: k.colors.bad),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(
                    l10n.catalogArchiveTitle(widget.name),
                    style: k.text.h3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.catalogArchiveBody,
                  style: k.text.body.copyWith(color: k.colors.ink2),
                ),
                const SizedBox(height: 16),
                FutureBuilder<ArchiveImpact>(
                  future: _impact,
                  builder: (context, snap) {
                    final impact = snap.data;
                    Widget row(String label, String? value) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: k.text.small.copyWith(
                                color: k.colors.muted,
                              ),
                            ),
                          ),
                          if (value == null)
                            const KSkeleton(width: 60)
                          else
                            Text(
                              value,
                              style: k.text.small.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    );
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: k.colors.soft,
                        borderRadius: BorderRadius.circular(KRadius.input),
                      ),
                      child: Column(
                        children: [
                          row(
                            l10n.catalogArchiveVariants,
                            impact == null
                                ? null
                                : l10n.catalogArchiveVariantsValue(
                                    impact.variants,
                                    impact.inStock,
                                  ),
                          ),
                          row(
                            l10n.catalogArchiveOpenOrders,
                            impact == null
                                ? null
                                : l10n.catalogArchiveOpenOrdersValue(
                                    impact.openOrders,
                                  ),
                          ),
                          row(
                            l10n.catalogArchiveOpenRfqs,
                            impact?.openRfqs.toString(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    KButton.outline(
                      label: l10n.uiCancel,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    KButton.danger(
                      label: l10n.catalogArchiveConfirm,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
