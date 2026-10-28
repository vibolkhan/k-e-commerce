import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/ui/k_ui.dart';
import '../../../core/ui/pages/loading_page.dart';
import '../../admin/presentation/admin_shell.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog_list.dart';
import '../domain/catalog_outcome.dart';
import '../domain/product_draft.dart';
import 'archive_dialog.dart';
import 'catalog_labels.dart';
import 'catalog_providers.dart';
import 'general_tab.dart';
import 'images_tab.dart';
import 'product_preview_sheet.dart';
import 'product_thumb.dart';
import 'variants_tab.dart';

/// A-05a – A-05c: create a product ([id] null) or edit one. Staff who may
/// only view products get the same screens read-only.
class ProductEditorPage extends ConsumerWidget {
  const ProductEditorPage({super.key, this.id});

  final String? id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final id = this.id;
    if (id == null) {
      return const ProductEditor(original: ProductDraft());
    }
    return switch (ref.watch(productDraftProvider(id))) {
      AsyncValue(:final value?) => ProductEditor(
        key: ValueKey(value.summary.updatedAt),
        original: value,
      ),
      AsyncValue(hasValue: true) => AdminPage(
        title: l10n.adminSectionCatalog,
        showBack: true,
        parent: AppRoutes.adminCatalog,
        children: [
          KEmptyState(icon: KIcons.package, title: l10n.catalogNotFound),
        ],
      ),
      AsyncValue(hasError: true) => AdminPage(
        title: l10n.adminSectionCatalog,
        showBack: true,
        parent: AppRoutes.adminCatalog,
        children: [
          KEmptyState(
            icon: KIcons.error,
            title: l10n.catalogErrUnknown,
            action: KButton.outline(
              label: l10n.catalogRetry,
              onPressed: () => ref.invalidate(productDraftProvider(id)),
            ),
          ),
        ],
      ),
      _ => const LoadingPage(),
    };
  }
}

class ProductEditor extends ConsumerStatefulWidget {
  const ProductEditor({super.key, required this.original});

  /// The saved product, or an empty draft for a new one.
  final ProductDraft original;

  @override
  ConsumerState<ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends ConsumerState<ProductEditor> {
  late var _draft = widget.original;
  var _issues = const <FieldIssue>[];
  var _tab = ProductTab.general;
  var _saving = false;

  /// Photos of a product that isn't saved yet go to a folder of their own.
  late final _uploadFolder =
      widget.original.id ??
      'new-${List.generate(12, (_) => Random.secure().nextInt(36).toRadixString(36)).join()}';

  bool get _dirty => !_draft.sameContentAs(widget.original);

  void _change(ProductDraft next) => setState(() {
    _draft = next;
    // A field the staff member touched no longer shows the old error.
    if (_issues.isNotEmpty) {
      final still = next.validate().toSet();
      _issues = [
        for (final issue in _issues)
          if (still.contains(issue)) issue,
      ];
    }
  });

  /// Variants whose saved price changes with this save.
  int get _priceChanges {
    final before = {
      for (final v in widget.original.variants)
        if (v.id != null) v.id!: v.priceCents,
    };
    return _draft.variants
        .where((v) => v.id != null && before[v.id] != v.priceCents)
        .length;
  }

  void _showIssues(List<FieldIssue> issues) {
    setState(() {
      _issues = issues;
      _tab = issues.first.tab;
    });
    _toast(AppLocalizations.of(context).catalogFixErrors, ok: false);
  }

  void _toast(String message, {required bool ok}) => showKToast(
    context,
    message: message,
    tone: ok ? KToastTone.ok : KToastTone.bad,
    icon: ok ? KIcons.success : KIcons.error,
  );

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final issues = _draft.validate();
    if (issues.isNotEmpty) return _showIssues(issues);

    final changes = _priceChanges;
    if (changes > 0) {
      final ok = await showKConfirm(
        context,
        title: l10n.catalogPriceConfirmTitle,
        message: l10n.catalogPriceConfirmBody(changes),
        confirmLabel: l10n.catalogPriceConfirm,
        cancelLabel: l10n.uiCancel,
        icon: KIcons.tag,
      );
      if (!ok || !mounted) return;
    }

    setState(() => _saving = true);
    final outcome = await ref.read(catalogRepositoryProvider).save(_draft);
    if (!mounted) return;
    setState(() => _saving = false);

    switch (outcome) {
      case CatalogSaved(:final id):
        _toast(
          _draft.isNew ? l10n.catalogSavedNew : l10n.catalogSaved,
          ok: true,
        );
        ref.invalidate(catalogPageProvider);
        if (_draft.isNew) {
          context.go(AppRoutes.adminProduct(id));
        } else {
          ref.invalidate(productDraftProvider(id));
          ref.invalidate(priceHistoryProvider(id));
          ref.invalidate(productViewProvider(id));
        }
      case CatalogInvalid(:final issues) when issues.isNotEmpty:
        _showIssues(issues);
      case CatalogSkuTaken(:final sku):
        final i = _draft.variants.indexWhere((v) => v.sku.trim() == sku);
        setState(() {
          _issues = [
            if (i >= 0) FieldIssue('variants.$i.sku', IssueCode.duplicate),
          ];
          _tab = ProductTab.variants;
        });
        _toast(l10n.catalogSkuTaken(sku), ok: false);
      default:
        _toast(outcomeMessage(l10n, outcome), ok: false);
    }
  }

  Future<void> _archive() async {
    final l10n = AppLocalizations.of(context);
    final id = _draft.id!;
    final name = widget.original.name.of(_lang);
    if (!await confirmArchive(context, productId: id, name: name)) return;
    if (!mounted) return;
    final outcome = await ref.read(catalogRepositoryProvider).archive(id);
    if (!mounted) return;
    if (outcome is CatalogUpdated) {
      _toast(l10n.catalogArchived(name), ok: true);
      ref.invalidate(catalogPageProvider);
      context.go(AppRoutes.adminCatalog);
    } else {
      _toast(outcomeMessage(l10n, outcome), ok: false);
    }
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    final id = _draft.id!;
    final outcome = await ref.read(catalogRepositoryProvider).restore(id);
    if (!mounted) return;
    if (outcome is CatalogUpdated) {
      _toast(l10n.catalogRestored(widget.original.name.of(_lang)), ok: true);
      ref.invalidate(catalogPageProvider);
      ref.invalidate(productDraftProvider(id));
    } else {
      _toast(outcomeMessage(l10n, outcome), ok: false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final l10n = AppLocalizations.of(context);
    // The safe choice (keep editing) is the primary button.
    final keep = await showKConfirm(
      context,
      title: l10n.catalogLeaveTitle,
      message: l10n.catalogLeaveBody,
      confirmLabel: l10n.catalogKeepEditing,
      cancelLabel: l10n.catalogLeave,
      icon: KIcons.warning,
      iconTone: KBannerTone.warn,
    );
    return !keep;
  }

  Future<void> _back() async {
    if (await _confirmLeave() && mounted) context.go(AppRoutes.adminCatalog);
  }

  String get _lang => Localizations.localeOf(context).languageCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final readOnly = !ref.watch(canEditCatalogProvider);
    final saved = widget.original;
    final archived = saved.status == ProductStatus.archived;
    final lang = _lang;

    final tabs = switch (_tab) {
      ProductTab.general => GeneralTab(
        draft: _draft,
        onChanged: _change,
        issues: _issues,
        readOnly: readOnly,
      ),
      ProductTab.variants => VariantsTab(
        draft: _draft,
        onChanged: _change,
        issues: _issues,
        readOnly: readOnly,
      ),
      ProductTab.images => ImagesTab(
        draft: _draft,
        onChanged: _change,
        issues: _issues,
        readOnly: readOnly,
        uploadFolder: _uploadFolder,
      ),
    };
    int errorsIn(ProductTab tab) => _issues.where((i) => i.tab == tab).length;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _confirmLeave() && context.mounted) {
          context.go(AppRoutes.adminCatalog);
        }
      },
      child: AdminPage(
        title: saved.isNew
            ? l10n.catalogNewProduct
            : saved.name.of(lang).isEmpty
            ? l10n.catalogNewProduct
            : saved.name.of(lang),
        showBack: true,
        parent: AppRoutes.adminCatalog,
        actions: [
          if (!saved.isNew)
            KButton.outline(
              label: l10n.catalogPreview,
              icon: KIcons.eye,
              size: KButtonSize.sm,
              onPressed: () => showProductPreview(
                context,
                productId: saved.id!,
                active: saved.status == ProductStatus.active,
                unsavedChanges: _dirty,
              ),
            ),
          if (!readOnly && !saved.isNew && !archived)
            KButton(
              label: l10n.catalogArchive,
              variant: KButtonVariant.dangerOutline,
              size: KButtonSize.sm,
              onPressed: _archive,
            ),
          if (!readOnly && archived)
            KButton.outline(
              label: l10n.catalogRestore,
              size: KButtonSize.sm,
              onPressed: _restore,
            ),
          if (!readOnly)
            KButton(
              label: saved.isNew ? l10n.catalogCreate : l10n.catalogSave,
              size: KButtonSize.sm,
              loading: _saving,
              onPressed: _saving || (!saved.isNew && !_dirty) ? null : _save,
            ),
        ],
        children: [
          _Header(draft: saved, onBack: _back),
          const SizedBox(height: 16),
          if (readOnly) ...[
            KBanner(message: l10n.catalogReadOnly, icon: KIcons.info),
            const SizedBox(height: 16),
          ],
          KTabs(
            tabs: [
              KTab(
                l10n.catalogTabGeneral,
                count: errorsIn(ProductTab.general) > 0
                    ? errorsIn(ProductTab.general)
                    : null,
              ),
              KTab(l10n.catalogTabVariants, count: _draft.variants.length),
              KTab(l10n.catalogTabImages, count: _draft.images.length),
            ],
            selectedIndex: _tab.index,
            onChanged: (i) => setState(() => _tab = ProductTab.values[i]),
          ),
          const SizedBox(height: 16),
          KeyedSubtree(key: ValueKey(_tab), child: tabs),
        ],
      ),
    );
  }
}

/// Breadcrumb, thumbnail, status and "HP-PRO · 3 variants · Audio".
class _Header extends ConsumerWidget {
  const _Header({required this.draft, required this.onBack});

  final ProductDraft draft;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final lang = Localizations.localeOf(context).languageCode;
    final categories = ref.watch(catalogCategoriesProvider).value ?? const [];
    final category = categoryTree(categories, lang)
        .where((e) => e.category.id == draft.categoryId)
        .map((e) => e.category.name.of(lang))
        .firstOrNull;
    final sub = [
      if (draft.variants.firstOrNull?.sku case final sku
          when sku != null && sku.isNotEmpty)
        sku,
      if (!draft.isNew) l10n.catalogVariantCount(draft.variants.length),
      ?category,
    ].join(' · ');

    return Row(
      children: [
        if (isAdminWide(context)) ...[
          KButton.ghost(
            label: l10n.catalogBreadcrumb,
            icon: KIcons.back,
            size: KButtonSize.sm,
            onPressed: onBack,
          ),
          const SizedBox(width: 12),
        ],
        if (!draft.isNew) ...[
          ProductThumb(url: draft.mainImage?.url, size: 44),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(sub, style: k.text.small.copyWith(color: k.colors.muted)),
        ),
        if (!draft.isNew)
          KStatusPill(
            label: statusLabel(l10n, draft.status),
            tone: statusTone(draft.status),
            dot: true,
          ),
      ],
    );
  }
}
