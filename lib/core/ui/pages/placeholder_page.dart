import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../k_ui.dart';

/// Stand-in for a screen a later task builds, so links to it (pushes, inbox
/// rows) already open the right place. Shows the design id and the record.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.screenId,
    required this.reference,
    required this.parent,
  });

  final String title;

  /// Design screen id, e.g. C-12.
  final String screenId;

  /// The order, quote or conversation id from the link.
  final String reference;

  /// Where back goes when the page was opened directly (a push tap).
  final String parent;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: KAppBar(
        title: title,
        line: true,
        showBack: true,
        onBack: () => context.canPop() ? context.pop() : context.go(parent),
      ),
      body: ListView(
        children: [
          KEmptyState(
            icon: KIcons.time,
            title: title,
            message: l10n.placeholderBody(screenId),
          ),
          Text(
            l10n.placeholderReference(reference),
            textAlign: TextAlign.center,
            style: k.text.caption.copyWith(color: k.colors.muted),
          ),
        ],
      ),
    );
  }
}
