import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/browse.dart';

/// "Most popular", or "Popular" on the chip ([short]).
String sortLabel(
  AppLocalizations l10n,
  BrowseSort sort, {
  bool short = false,
}) => switch (sort) {
  BrowseSort.popular || BrowseSort.curated =>
    short ? l10n.storeSortPopularShort : l10n.storeSortPopular,
  BrowseSort.newest => l10n.storeSortNewest,
  BrowseSort.priceAsc => l10n.storeSortPriceAsc,
  BrowseSort.priceDesc => l10n.storeSortPriceDesc,
  BrowseSort.rating => l10n.storeSortRating,
};

/// C-03b Sort by. Business buyers get no price options. Resolves with the
/// chosen sort, or null if closed.
Future<BrowseSort?> showSortSheet(
  BuildContext context, {
  required BrowseSort current,
  required bool business,
}) {
  return showKBottomSheet<BrowseSort>(
    context,
    title: AppLocalizations.of(context).storeSortBy,
    builder: (_) => SortSheet(current: current, business: business),
  );
}

class SortSheet extends StatefulWidget {
  const SortSheet({super.key, required this.current, required this.business});

  final BrowseSort current;
  final bool business;

  @override
  State<SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<SortSheet> {
  late BrowseSort _picked = widget.current == BrowseSort.curated
      ? BrowseSort.popular
      : widget.current;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final s in BrowseSort.options(business: widget.business))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: KOptionTile(
                      key: Key('sort-${s.wire}'),
                      title: sortLabel(l10n, s),
                      subtitle: s == BrowseSort.popular
                          ? l10n.storeSortPopularHint
                          : null,
                      selected: s == _picked,
                      onTap: () => setState(() => _picked = s),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        KButton(
          key: const Key('sort-apply'),
          label: l10n.storeApply,
          size: KButtonSize.lg,
          expand: true,
          onPressed: () => Navigator.of(context).pop(_picked),
        ),
      ],
    );
  }
}
