import 'package:flutter/widgets.dart';

import '../../../core/ui/k_ui.dart';

/// A k-ui `.panel`: bordered card with a title bar, used across back-office
/// pages (A-14d, A-05).
class AdminPanel extends StatelessWidget {
  const AdminPanel({
    super.key,
    required this.head,
    required this.child,
    this.headTrailing,
  });

  final Widget head;
  final Widget? headTrailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(KRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                Expanded(child: head),
                if (headTrailing != null) ...[
                  const SizedBox(width: 12),
                  headTrailing!,
                ],
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Panel heading with an optional muted line under it.
class AdminPanelTitle extends StatelessWidget {
  const AdminPanelTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: k.text.title.copyWith(
              fontSize: 16,
              height: 22 / 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: k.text.caption.copyWith(color: k.colors.muted),
          ),
      ],
    );
  }
}
