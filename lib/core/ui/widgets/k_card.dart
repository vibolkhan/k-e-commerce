import 'package:flutter/material.dart';

import '../icons/k_icon.dart';
import '../icons/k_icons.dart';
import '../theme/k_theme.dart';
import '../theme/k_tokens.dart';

enum KCardStyle {
  /// White, 1 px line border — the default.
  outlined,

  /// Floating: level 2 shadow, no border.
  shadow,

  /// Sky 50 with a sky 100 border, for tips and highlights.
  tint,
}

/// Surface for grouped content: radius 16, padding 16.
class KCard extends StatelessWidget {
  const KCard({
    super.key,
    required this.child,
    this.style = KCardStyle.outlined,
    this.padding = const EdgeInsets.all(KSpacing.x4),
    this.onTap,
    this.clip = false,
  });

  final Widget child;
  final KCardStyle style;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Clip children to the rounded corners (lists, images).
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final (bg, border, shadow) = switch (style) {
      KCardStyle.outlined => (c.surface, c.line, null),
      KCardStyle.shadow => (c.surface, Colors.transparent, k.shadow2),
      KCardStyle.tint => (c.tint, c.tint2, null),
    };
    final radius = BorderRadius.circular(KRadius.card);
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, borderRadius: radius, child: content),
      );
    }
    return Container(
      clipBehavior: clip || onTap != null ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: Border.all(color: border),
        boxShadow: shadow,
      ),
      child: content,
    );
  }
}

/// Vertical list with 1 px dividers between rows.
class KList extends StatelessWidget {
  const KList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final line = context.k.colors.line;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: line),
          child,
        ],
      ],
    );
  }
}

/// 56 px row: optional icon tile, title + subtitle, trailing (chevron by
/// default when tappable).
class KListRow extends StatelessWidget {
  const KListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.trailing,
    this.onTap,
    this.showChevron,
  });

  final String title;
  final String? subtitle;

  /// Shown in a 40 px soft tile.
  final KIconData? icon;

  /// Replaces [icon] (avatar, thumbnail).
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Defaults to true when [onTap] is set and there is no [trailing].
  final bool? showChevron;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final chevron = showChevron ?? (onTap != null && trailing == null);
    return Material(
      color: c.surface,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 12),
                ] else if (icon != null) ...[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.soft,
                      borderRadius: BorderRadius.circular(KRadius.input),
                    ),
                    alignment: Alignment.center,
                    child: KIcon(icon!, size: 20, color: c.ink2),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: k.text.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: k.text.small.copyWith(color: c.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
                if (chevron) ...[
                  const SizedBox(width: 12),
                  KIcon(KIcons.chevronRight, size: 20, color: c.muted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
