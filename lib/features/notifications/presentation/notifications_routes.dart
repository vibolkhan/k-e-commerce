import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_role.dart';
import '../../../core/ui/pages/placeholder_page.dart';
import 'inbox_page.dart';

/// Under the shell's home: S-07 and the screens notifications open, on the
/// root navigator (over the bottom navigation). Guests have no inbox and
/// land on home.
List<GoRoute> notificationRoutes(
  AppRole role, {
  required GlobalKey<NavigatorState> rootKey,
  required bool Function() isSignedIn,
}) {
  final shell = role.homePath;
  String? signedInOnly(BuildContext _, GoRouterState _) =>
      isSignedIn() ? null : shell;
  GoRoute placeholder(
    String path,
    String screenId,
    String Function(AppLocalizations) title,
  ) => GoRoute(
    path: path,
    parentNavigatorKey: rootKey,
    redirect: signedInOnly,
    builder: (context, state) => PlaceholderPage(
      title: title(AppLocalizations.of(context)),
      screenId: screenId,
      reference: state.pathParameters['id']!,
      parent: shell,
    ),
  );
  return [
    GoRoute(
      path: 'inbox',
      parentNavigatorKey: rootKey,
      redirect: signedInOnly,
      builder: (_, _) => InboxPage(shell: shell),
    ),
    placeholder('orders/:id', 'C-12', (l10n) => l10n.placeholderOrderTitle),
    placeholder('chat/:id', 'C-17', (l10n) => l10n.placeholderChatTitle),
    if (role == AppRole.business)
      placeholder('quotes/:id', 'B-05', (l10n) => l10n.placeholderQuoteTitle),
  ];
}
