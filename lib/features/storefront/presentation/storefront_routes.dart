import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_role.dart';
import '../../../core/ui/pages/placeholder_page.dart';
import 'categories_page.dart';
import 'product_detail/product_detail_page.dart';
import 'product_list_page.dart';
import 'search_page.dart';

/// Under the shell's home: collections from home rails and banners (C-03),
/// search (C-04), product detail (C-05) and the placeholders home links to,
/// on the root navigator.
List<GoRoute> homeBrowseRoutes(
  AppRole role, {
  required GlobalKey<NavigatorState> rootKey,
}) {
  final shell = role.homePath;
  GoRoute placeholder(
    String path,
    String screenId,
    String Function(AppLocalizations) title, {
    String? Function(GoRouterState)? reference,
  }) => GoRoute(
    path: path,
    parentNavigatorKey: rootKey,
    builder: (context, state) => PlaceholderPage(
      title: title(AppLocalizations.of(context)),
      screenId: screenId,
      reference: reference?.call(state),
      parent: shell,
    ),
  );
  return [
    GoRoute(
      path: 'collections/:slug',
      builder: (_, state) =>
          ProductListPage(role: role, collection: state.pathParameters['slug']),
    ),
    GoRoute(
      path: 'search',
      parentNavigatorKey: rootKey,
      builder: (_, state) =>
          SearchPage(role: role, initialQuery: state.uri.queryParameters['q']),
    ),
    if (role == AppRole.business)
      placeholder(
        'products/:id',
        'B-00a',
        (l10n) => l10n.storeProductTitle,
        reference: (state) => state.pathParameters['id'],
      )
    else ...[
      GoRoute(
        path: 'products/:id',
        parentNavigatorKey: rootKey,
        builder: (_, state) =>
            ProductDetailPage(role: role, id: state.pathParameters['id']!),
      ),
      placeholder('cart', 'C-06', (l10n) => l10n.navCart),
    ],
    if (role == AppRole.customer)
      placeholder(
        'business-upgrade',
        'B-01',
        (l10n) => l10n.storeBusinessUpgradeTitle,
      ),
  ];
}

/// The Categories tab: C-02, and C-03 for one category.
GoRoute categoriesRoute(AppRole role) => GoRoute(
  path: '${role.homePath}/categories',
  builder: (_, _) => CategoriesPage(role: role),
  routes: [
    GoRoute(
      path: ':slug',
      builder: (_, state) => ProductListPage(
        role: role,
        categorySlug: state.pathParameters['slug'],
      ),
    ),
  ],
);
