import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../router/app_routes.dart';

enum ErrorKind { notFound, forbidden, generic }

class ErrorPage extends StatelessWidget {
  const ErrorPage({super.key, this.kind = ErrorKind.generic});
  const ErrorPage.notFound({super.key}) : kind = ErrorKind.notFound;
  const ErrorPage.forbidden({super.key}) : kind = ErrorKind.forbidden;

  final ErrorKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (icon, title, message) = switch (kind) {
      ErrorKind.notFound => (
        Icons.search_off,
        l10n.notFoundTitle,
        l10n.notFoundMessage,
      ),
      ErrorKind.forbidden => (
        Icons.lock_outline,
        l10n.forbiddenTitle,
        l10n.forbiddenMessage,
      ),
      ErrorKind.generic => (
        Icons.error_outline,
        l10n.errorTitle,
        l10n.errorMessage,
      ),
    };
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go(AppRoutes.root),
                child: Text(l10n.goHome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
