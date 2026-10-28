import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/time/date_format.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/catalog_list.dart';
import '../domain/i18n_text.dart';
import '../domain/product_draft.dart';
import 'catalog_providers.dart';
import 'category_picker.dart';
import 'editor_widgets.dart';

/// A-05a General: names and descriptions in both languages, highlights,
/// specifications, organisation, visibility and the summary.
class GeneralTab extends ConsumerStatefulWidget {
  const GeneralTab({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.issues,
    required this.readOnly,
  });

  final ProductDraft draft;
  final ValueChanged<ProductDraft> onChanged;
  final List<FieldIssue> issues;
  final bool readOnly;

  @override
  ConsumerState<GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends ConsumerState<GeneralTab> {
  final _highlightKeys = RowKeys();
  final _specKeys = RowKeys();
  final _tag = TextEditingController();

  ProductDraft get draft => widget.draft;
  void _set(ProductDraft next) => widget.onChanged(next);

  @override
  void dispose() {
    _tag.dispose();
    super.dispose();
  }

  void _addTag(String text) {
    final tag = text.trim();
    _tag.clear();
    if (tag.isEmpty || draft.tags.contains(tag)) return;
    if (draft.tags.length >= CatalogLimits.tags) return;
    _set(draft.copyWith(tags: [...draft.tags, tag]));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ro = widget.readOnly;
    String? err(String field) => issueFor(l10n, widget.issues, field);

    return EditorColumns(
      main: [
        EditorCard(
          title: l10n.catalogBasicInfo,
          subtitle: l10n.catalogBasicInfoSub,
          children: [
            KTextField(
              label: l10n.catalogNameEn,
              initialValue: draft.name.en,
              readOnly: ro,
              maxLength: CatalogLimits.name,
              errorText: err('name.en'),
              onChanged: (v) =>
                  _set(draft.copyWith(name: draft.name.copyWith(en: v))),
            ),
            TranslationMissing(
              show: draft.name.missingKm,
              child: KTextField(
                label: l10n.catalogNameKm,
                hint: l10n.catalogNameKmHint,
                initialValue: draft.name.km,
                readOnly: ro,
                maxLength: CatalogLimits.name,
                errorText: err('name.km'),
                onChanged: (v) =>
                    _set(draft.copyWith(name: draft.name.copyWith(km: v))),
              ),
            ),
            KTextField(
              label: l10n.catalogDescEn,
              initialValue: draft.description.en,
              readOnly: ro,
              maxLines: 5,
              errorText: err('description.en'),
              helpText: l10n.catalogCharCount(
                draft.description.en.length,
                CatalogLimits.description,
              ),
              onChanged: (v) => _set(
                draft.copyWith(description: draft.description.copyWith(en: v)),
              ),
            ),
            TranslationMissing(
              show: draft.description.missingKm,
              child: KTextField(
                label: l10n.catalogDescKm,
                hint: l10n.catalogDescKmHint,
                initialValue: draft.description.km,
                readOnly: ro,
                maxLines: 5,
                errorText: err('description.km'),
                helpText: l10n.catalogCharCount(
                  draft.description.km.length,
                  CatalogLimits.description,
                ),
                onChanged: (v) => _set(
                  draft.copyWith(
                    description: draft.description.copyWith(km: v),
                  ),
                ),
              ),
            ),
            _Highlights(
              highlights: draft.highlights,
              keys: _highlightKeys,
              readOnly: ro,
              issues: widget.issues,
              onChanged: (list) => _set(draft.copyWith(highlights: list)),
            ),
          ],
        ),
        _Specs(
          specs: draft.specs,
          keys: _specKeys,
          readOnly: ro,
          issues: widget.issues,
          onChanged: (list) => _set(draft.copyWith(specs: list)),
        ),
      ],
      side: [
        EditorCard(
          title: l10n.catalogOrganisation,
          children: [
            _CategoryField(
              categoryId: draft.categoryId,
              error: err('category_id') ?? err('category'),
              onPick: ro
                  ? null
                  : (c) => _set(draft.copyWith(categoryId: () => c.id)),
            ),
            KTextField(
              label: l10n.catalogBrand,
              initialValue: draft.brand,
              readOnly: ro,
              optional: true,
              onChanged: (v) => _set(draft.copyWith(brand: v)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.catalogTags,
                  style: context.k.text.label.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in draft.tags)
                      _RemovableChip(
                        label: tag,
                        removeLabel: l10n.catalogRemoveTag(tag),
                        onRemove: ro
                            ? null
                            : () => _set(
                                draft.copyWith(
                                  tags: [...draft.tags]..remove(tag),
                                ),
                              ),
                      ),
                  ],
                ),
                if (!ro) ...[
                  const SizedBox(height: 8),
                  KTextField(
                    controller: _tag,
                    hint: l10n.catalogTagHint,
                    textInputAction: TextInputAction.done,
                    onSubmitted: _addTag,
                  ),
                ],
              ],
            ),
          ],
        ),
        EditorCard(
          title: l10n.catalogVisibility,
          children: [
            SwitchTile(
              title: l10n.catalogActive,
              subtitle: l10n.catalogActiveSub,
              value: draft.status == ProductStatus.active,
              onChanged: ro || draft.status == ProductStatus.archived
                  ? null
                  : (on) => _set(
                      draft.copyWith(
                        status: on ? ProductStatus.active : ProductStatus.draft,
                      ),
                    ),
            ),
            SwitchTile(
              title: l10n.catalogBestSeller,
              subtitle: l10n.catalogBestSellerSub,
              value: draft.isBestSeller,
              onChanged: ro
                  ? null
                  : (on) => _set(draft.copyWith(isBestSeller: on)),
            ),
            SwitchTile(
              title: l10n.catalogSameDay,
              subtitle: l10n.catalogSameDaySub,
              value: draft.sameDay,
              onChanged: ro ? null : (on) => _set(draft.copyWith(sameDay: on)),
            ),
          ],
        ),
        if (!draft.isNew) _Summary(summary: draft.summary),
      ],
    );
  }
}

class _Highlights extends StatelessWidget {
  const _Highlights({
    required this.highlights,
    required this.keys,
    required this.readOnly,
    required this.issues,
    required this.onChanged,
  });

  final List<I18nText> highlights;
  final RowKeys keys;
  final bool readOnly;
  final List<FieldIssue> issues;
  final ValueChanged<List<I18nText>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.catalogHighlights,
          style: k.text.label.copyWith(fontWeight: FontWeight.w600),
        ),
        for (var i = 0; i < highlights.length; i++)
          Padding(
            key: ValueKey(keys.at(i, highlights.length)),
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: KTextField(
                    hint: l10n.catalogHighlightEn,
                    initialValue: highlights[i].en,
                    readOnly: readOnly,
                    errorText: issueFor(l10n, issues, 'highlights.$i.en'),
                    onChanged: (v) => onChanged([
                      ...highlights.take(i),
                      highlights[i].copyWith(en: v),
                      ...highlights.skip(i + 1),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KTextField(
                    hint: l10n.catalogHighlightKm,
                    initialValue: highlights[i].km,
                    readOnly: readOnly,
                    onChanged: (v) => onChanged([
                      ...highlights.take(i),
                      highlights[i].copyWith(km: v),
                      ...highlights.skip(i + 1),
                    ]),
                  ),
                ),
                if (!readOnly)
                  KIconButton(
                    icon: KIcons.close,
                    label: l10n.catalogRemoveHighlight,
                    onPressed: () {
                      keys.removeAt(i);
                      onChanged([...highlights]..removeAt(i));
                    },
                  ),
              ],
            ),
          ),
        if (!readOnly && highlights.length < CatalogLimits.highlights) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: KButton.ghost(
              label: l10n.catalogAddHighlight,
              icon: KIcons.plus,
              size: KButtonSize.sm,
              onPressed: () => onChanged([...highlights, const I18nText()]),
            ),
          ),
        ],
      ],
    );
  }
}

class _Specs extends StatelessWidget {
  const _Specs({
    required this.specs,
    required this.keys,
    required this.readOnly,
    required this.issues,
    required this.onChanged,
  });

  final List<Spec> specs;
  final RowKeys keys;
  final bool readOnly;
  final List<FieldIssue> issues;
  final ValueChanged<List<Spec>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    void put(int i, Spec spec) =>
        onChanged([...specs.take(i), spec, ...specs.skip(i + 1)]);
    return EditorCard(
      title: l10n.catalogSpecs,
      children: [
        for (var i = 0; i < specs.length; i++)
          Row(
            key: ValueKey(keys.at(i, specs.length)),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: KTextField(
                  hint: l10n.catalogSpecName,
                  initialValue: specs[i].name,
                  readOnly: readOnly,
                  errorText: issueFor(l10n, issues, 'specs.$i.name'),
                  onChanged: (v) => put(i, specs[i].copyWith(name: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: KTextField(
                  hint: l10n.catalogSpecValue,
                  initialValue: specs[i].value,
                  readOnly: readOnly,
                  errorText: issueFor(l10n, issues, 'specs.$i.value'),
                  onChanged: (v) => put(i, specs[i].copyWith(value: v)),
                ),
              ),
              if (!readOnly)
                KIconButton(
                  icon: KIcons.close,
                  label: l10n.catalogRemoveSpec,
                  onPressed: () {
                    keys.removeAt(i);
                    onChanged([...specs]..removeAt(i));
                  },
                ),
            ],
          ),
        if (!readOnly && specs.length < CatalogLimits.specs)
          Align(
            alignment: Alignment.centerLeft,
            child: KButton.ghost(
              label: l10n.catalogAddSpec,
              icon: KIcons.plus,
              size: KButtonSize.sm,
              onPressed: () => onChanged([...specs, const Spec()]),
            ),
          ),
      ],
    );
  }
}

class _CategoryField extends ConsumerWidget {
  const _CategoryField({
    required this.categoryId,
    required this.error,
    required this.onPick,
  });

  final String? categoryId;
  final String? error;
  final ValueChanged<Category>? onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final categories = ref.watch(catalogCategoriesProvider).value ?? const [];
    final path = categoryTree(
      categories,
      lang,
    ).where((e) => e.category.id == categoryId).map((e) => e.path);
    return KTextField(
      key: ValueKey('category-${path.firstOrNull}'),
      label: l10n.catalogCategory,
      hint: l10n.catalogChooseCategory,
      initialValue: path.firstOrNull ?? '',
      readOnly: true,
      errorText: error,
      suffix: const KIcon(KIcons.chevronDown, size: 18),
      onTap: onPick == null
          ? null
          : () async {
              final picked = await pickCategory(
                context,
                ref,
                selectedId: categoryId,
              );
              if (picked != null) onPick!(picked);
            },
    );
  }
}

class _RemovableChip extends StatelessWidget {
  const _RemovableChip({
    required this.label,
    required this.removeLabel,
    required this.onRemove,
  });

  final String label;
  final String removeLabel;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Container(
      padding: EdgeInsets.only(left: 12, right: onRemove == null ? 12 : 0),
      decoration: BoxDecoration(
        color: k.colors.soft,
        border: Border.all(color: k.colors.line),
        borderRadius: BorderRadius.circular(KRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(label, style: k.text.small),
          ),
          if (onRemove != null)
            KIconButton(
              icon: KIcons.close,
              label: removeLabel,
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.summary});

  final ProductSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    String byOn(DateTime? at, String? name) => at == null
        ? '—'
        : l10n.catalogByOn(
            formatDayMonth(l10n, at),
            name ?? l10n.catalogUnknownStaff,
          );
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: k.text.small.copyWith(color: k.colors.muted),
            ),
          ),
          Text(
            value,
            style: k.text.small.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return EditorCard(
      title: l10n.catalogSummary,
      children: [
        Column(
          children: [
            row(
              l10n.catalogCreatedLabel,
              byOn(summary.createdAt, summary.createdBy),
            ),
            row(
              l10n.catalogLastUpdated,
              byOn(summary.updatedAt, summary.updatedBy),
            ),
            row(l10n.catalogSoldCount, '${summary.soldCount}'),
            row(
              l10n.catalogRating,
              l10n.catalogRatingValue(
                summary.ratingAvg.toStringAsFixed(1),
                summary.ratingCount,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
