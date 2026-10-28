import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import '../../admin/presentation/admin_panel.dart';
import '../../admin/presentation/admin_shell.dart';
import '../domain/product_draft.dart';
import 'catalog_labels.dart';

/// A titled panel with padded content (A-05a – A-05c cards).
class EditorCard extends StatelessWidget {
  const EditorCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AdminPanel(
    head: AdminPanelTitle(title, subtitle: subtitle),
    headTrailing: trailing,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            children[i],
          ],
        ],
      ),
    ),
  );
}

/// Main column and side column on desktop; stacked on phones.
class EditorColumns extends StatelessWidget {
  const EditorColumns({super.key, required this.main, required this.side});

  final List<Widget> main;
  final List<Widget> side;

  @override
  Widget build(BuildContext context) {
    List<Widget> spaced(List<Widget> items) => [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(height: 16),
        items[i],
      ],
    ];
    if (!isAdminWide(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: spaced([...main, ...side]),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: spaced(main),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: spaced(side),
          ),
        ),
      ],
    );
  }
}

/// A switch with a title and a muted line under it (A-05a Visibility).
class SwitchTile extends StatelessWidget {
  const SwitchTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinTap),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: k.text.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    style: k.text.caption.copyWith(color: k.colors.muted),
                  ),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// The amber "Translation missing" flag beside a Khmer field.
class TranslationMissing extends StatelessWidget {
  const TranslationMissing({
    super.key,
    required this.child,
    required this.show,
  });

  final Widget child;
  final bool show;

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          right: 0,
          child: KStatusPill(
            label: AppLocalizations.of(context).catalogTranslationMissing,
            tone: KTone.amber,
          ),
        ),
      ],
    );
  }
}

/// The message for [field] among [issues], if any.
String? issueFor(AppLocalizations l10n, List<FieldIssue> issues, String field) {
  for (final issue in issues) {
    if (issue.field == field) return issueMessage(l10n, issue);
  }
  return null;
}

/// Stable keys for the rows of an editable list, so removing a row keeps
/// the other rows' text fields in place.
class RowKeys {
  final _keys = <int>[];
  var _next = 0;

  int at(int index, int length) {
    while (_keys.length < length) {
      _keys.add(_next++);
    }
    if (_keys.length > length) _keys.removeRange(length, _keys.length);
    return _keys[index];
  }

  void removeAt(int index) {
    if (index < _keys.length) _keys.removeAt(index);
  }

  void move(int from, int to) {
    if (from >= _keys.length || to >= _keys.length) return;
    final key = _keys.removeAt(from);
    _keys.insert(to, key);
  }
}
