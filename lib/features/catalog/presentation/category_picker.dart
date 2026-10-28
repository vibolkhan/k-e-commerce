import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/catalog_list.dart';
import '../domain/i18n_text.dart';
import 'catalog_providers.dart';

/// Picks a category from the tree. With [allowAll], the first row is "All
/// categories" and returns a category with an empty id.
Future<Category?> pickCategory(
  BuildContext context,
  WidgetRef ref, {
  bool allowAll = false,
  String? selectedId,
}) {
  final l10n = AppLocalizations.of(context);
  return showKBottomSheet<Category>(
    context,
    title: allowAll ? l10n.catalogFilterCategory : l10n.catalogChooseCategory,
    builder: (_) => _CategoryList(allowAll: allowAll, selectedId: selectedId),
  );
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.allowAll, this.selectedId});

  final bool allowAll;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final categories = ref.watch(catalogCategoriesProvider);
    return switch (categories) {
      AsyncValue(:final value?) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            if (allowAll)
              _Row(
                label: l10n.catalogAllCategories,
                depth: 0,
                selected: selectedId == null,
                onTap: () => Navigator.of(
                  context,
                ).pop(const Category(id: '', name: I18nText())),
              ),
            for (final entry in categoryTree(value, lang))
              _Row(
                label: entry.category.name.of(lang),
                depth: entry.depth,
                selected: entry.category.id == selectedId,
                onTap: () => Navigator.of(context).pop(entry.category),
              ),
          ],
        ),
      ),
      AsyncValue(hasError: true) => KEmptyState(
        icon: KIcons.error,
        title: l10n.catalogErrUnknown,
        compact: true,
      ),
      _ => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: KSpinner()),
      ),
    };
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.depth,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int depth;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16 + depth * 20.0, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: (depth == 0 ? k.text.label : k.text.body).copyWith(
                      fontWeight: depth == 0 ? FontWeight.w700 : null,
                    ),
                  ),
                ),
                if (selected)
                  KIcon(KIcons.check, size: 20, color: k.colors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
