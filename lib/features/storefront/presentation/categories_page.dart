import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_role.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/browse.dart';
import '../domain/storefront.dart';
import 'home_page.dart' show CategoryTile, storeMaxWidth;
import 'store_widgets.dart';
import 'storefront_providers.dart';

/// C-02 Categories (CAT-02): top categories in a left rail; the right pane
/// shows the selected one's banner, its subcategories and what is popular
/// in it.
class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key, required this.role});

  final AppRole role;

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final shell = widget.role.homePath;
    final tree = ref.watch(storeCategoriesProvider);
    final Widget body;
    if (tree.hasError && !tree.hasValue) {
      body = KEmptyState(
        icon: KIcons.error,
        title: l10n.storeLoadFailed,
        action: KButton.outline(
          label: l10n.storeRetry,
          onPressed: () => ref.invalidate(storeCategoriesProvider),
        ),
      );
    } else if (!tree.hasValue) {
      body = const _CategoriesSkeleton();
    } else {
      final top = tree.value!.top;
      if (top.isEmpty) {
        body = KEmptyState(
          icon: KIcons.categories,
          title: l10n.storeNoCategories,
          message: l10n.storeNoCategoriesBody,
        );
      } else {
        final selected =
            top.where((c) => c.id == _selectedId).firstOrNull ?? top.first;
        body = Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: storeMaxWidth),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Rail(
                  categories: top,
                  selectedId: selected.id,
                  onSelect: (c) => setState(() => _selectedId = c.id),
                ),
                Expanded(
                  child: _Pane(
                    key: ValueKey(selected.id),
                    role: widget.role,
                    category: selected,
                    children: tree.value!.childrenOf(selected.id),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return Scaffold(
      backgroundColor: k.colors.bg,
      appBar: KAppBar(
        title: l10n.navCategories,
        centerTitle: false,
        line: true,
        showBack: false,
        actions: [
          KIconButton(
            icon: KIcons.search,
            label: l10n.storeSearchProducts,
            onPressed: () => context.push(AppRoutes.search(shell)),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  final List<StoreCategory> categories;
  final String selectedId;
  final ValueChanged<StoreCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final lang = Localizations.localeOf(context).languageCode;
    return Container(
      width: 104,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.line)),
      ),
      child: ListView(
        key: const Key('category-rail'),
        children: [
          for (final cat in categories)
            _RailItem(
              label: cat.name.of(lang),
              icon: categoryIcon(cat.icon),
              selected: cat.id == selectedId,
              onTap: () => onSelect(cat),
            ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final KIconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final fg = selected ? c.primaryInk : c.ink2;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.tint2 : c.surface,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 66),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  KIcon(icon, size: 24, color: fg),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: k.text.caption.copyWith(
                      height: 15 / 12,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pane extends ConsumerWidget {
  const _Pane({
    super.key,
    required this.role,
    required this.category,
    required this.children,
  });

  final AppRole role;
  final StoreCategory category;
  final List<StoreCategory> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final shell = role.homePath;
    final name = category.name.of(lang);
    final popular = ref.watch(
      categoryPopularProvider((id: category.id, viewer: watchViewer(ref))),
    );
    final items = popular.value ?? const <BrowseItem>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(name, style: k.text.h3),
              ),
            ),
            KButton.ghost(
              key: const Key('category-see-all'),
              label: l10n.storeSeeAll,
              size: KButtonSize.sm,
              onPressed: () =>
                  context.push(AppRoutes.category(shell, category.slug)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (category.bannerUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(KRadius.card),
            child: AspectRatio(
              aspectRatio: 16 / 7,
              child: KNetworkImage(
                url: category.bannerUrl,
                semanticLabel: name,
                fallback: const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (role != AppRole.business) ...[
          const SameDayBanner(compact: true),
          const SizedBox(height: 16),
        ],
        if (children.isNotEmpty)
          LayoutBuilder(
            builder: (context, box) {
              final columns = (box.maxWidth / 96).floor().clamp(3, 8);
              final width = (box.maxWidth - (columns - 1) * 8) / columns;
              return Wrap(
                spacing: 8,
                runSpacing: 12,
                children: [
                  for (final sub in children)
                    SizedBox(
                      width: width,
                      child: CategoryTile(
                        category: sub,
                        onTap: () =>
                            context.push(AppRoutes.category(shell, sub.slug)),
                      ),
                    ),
                ],
              );
            },
          ),
        if (popular.isLoading && !popular.hasValue) ...[
          StoreSectionHead(title: l10n.storePopularIn(name)),
          const StoreProductGrid(
            minTileWidth: 120,
            children: [ProductCardSkeleton(), ProductCardSkeleton()],
          ),
        ] else if (items.isNotEmpty) ...[
          StoreSectionHead(title: l10n.storePopularIn(name)),
          StoreProductGrid(
            minTileWidth: 120,
            children: [
              for (final item in items)
                StoreProductCard(item: item, role: role),
            ],
          ),
        ] else if (children.isEmpty)
          KEmptyState(
            compact: true,
            icon: KIcons.package,
            title: l10n.storeCategoryEmpty,
            message: l10n.storeCategoryEmptyBody,
          ),
      ],
    );
  }
}

class _CategoriesSkeleton extends StatelessWidget {
  const _CategoriesSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 104,
          color: c.surface,
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              for (var i = 0; i < 6; i++) ...[
                const KSkeleton(width: 24, height: 24),
                const SizedBox(height: 6),
                const KSkeleton(width: 56),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KSkeleton(width: 120, height: 20),
                SizedBox(height: 16),
                KSkeleton(height: 44, radius: 14),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
