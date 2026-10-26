import 'package:flutter/material.dart';

import '../icons/k_icon.dart';
import '../theme/k_theme.dart';
import '../theme/k_tokens.dart';
import 'k_basics.dart';

enum KButtonVariant { primary, tonal, outline, ghost, danger, dangerOutline }

/// Heights 36 / 48 / 56. Small buttons go only inside cards and tables and
/// still get a 44 px tap area.
enum KButtonSize { sm, md, lg }

/// The K button. One primary per screen; destructive actions use [danger]
/// behind a confirmation.
class KButton extends StatelessWidget {
  const KButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = KButtonVariant.primary,
    this.size = KButtonSize.md,
    this.icon,
    this.loading = false,
    this.loadingLabel,
    this.expand = false,
  });

  const KButton.tonal({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = KButtonSize.md,
    this.icon,
    this.loading = false,
    this.loadingLabel,
    this.expand = false,
  }) : variant = KButtonVariant.tonal;

  const KButton.outline({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = KButtonSize.md,
    this.icon,
    this.loading = false,
    this.loadingLabel,
    this.expand = false,
  }) : variant = KButtonVariant.outline;

  const KButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = KButtonSize.md,
    this.icon,
    this.loading = false,
    this.loadingLabel,
    this.expand = false,
  }) : variant = KButtonVariant.ghost;

  const KButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = KButtonSize.md,
    this.icon,
    this.loading = false,
    this.loadingLabel,
    this.expand = false,
  }) : variant = KButtonVariant.danger;

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final KButtonVariant variant;
  final KButtonSize size;
  final KIconData? icon;

  /// Shows a spinner and ignores taps; the button keeps its colours.
  final bool loading;

  /// Text shown while [loading] (e.g. "Placing…"); defaults to [label].
  final String? loadingLabel;

  /// Fill the available width.
  final bool expand;

  bool get _enabled => onPressed != null;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final (height, radius, padding, fontSize) = switch (size) {
      KButtonSize.sm => (36.0, KRadius.buttonSm, 14.0, 14.0),
      KButtonSize.md => (48.0, KRadius.input, 20.0, 15.0),
      KButtonSize.lg => (56.0, KRadius.box, 20.0, 16.0),
    };
    var (bg, fg, border) = switch (variant) {
      KButtonVariant.primary => (c.primary, Colors.white, null),
      KButtonVariant.tonal => (c.tint2, c.primaryInk, null),
      KButtonVariant.outline => (c.surface, c.ink, c.line2),
      KButtonVariant.ghost => (Colors.transparent, c.primary, null),
      KButtonVariant.danger => (c.badFill, Colors.white, null),
      KButtonVariant.dangerOutline => (c.surface, c.bad, KColors.badLine),
    };
    if (!_enabled && !loading) {
      (bg, fg, border) = (c.line, c.muted, null);
    }
    final onDark =
        variant == KButtonVariant.primary || variant == KButtonVariant.danger;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: border == null ? BorderSide.none : BorderSide(color: border),
    );
    final text = Text(
      loading ? (loadingLabel ?? label) : label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: k.text.button.copyWith(fontSize: fontSize, height: 1, color: fg),
    );
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading) ...[
          KSpinner(blue: !onDark),
          const SizedBox(width: KSpacing.x2),
        ] else if (icon != null) ...[
          KIcon(icon!, size: 20, color: fg),
          const SizedBox(width: KSpacing.x2),
        ],
        Flexible(child: text),
      ],
    );
    final button = Material(
      color: bg,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: loading ? null : onPressed,
        overlayColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.pressed)
              ? (onDark ? Colors.black : c.primary).withValues(alpha: 0.12)
              : s.contains(WidgetState.hovered) ||
                    s.contains(WidgetState.focused)
              ? (onDark ? Colors.black : c.primary).withValues(alpha: 0.06)
              : null,
        ),
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: content,
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: _enabled && !loading,
      label: label,
      excludeSemantics: true,
      onTap: loading ? null : onPressed,
      child: SizedBox(
        width: expand ? double.infinity : null,
        // Keep a 44 px tap area for the 36 px size.
        height: height < kMinTap ? kMinTap : null,
        child: height < kMinTap ? Center(child: button) : button,
      ),
    );
  }
}

enum KIconButtonStyle { plain, soft, white, outline }

/// 44 px icon-only button. Always has an accessible [label].
class KIconButton extends StatelessWidget {
  const KIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.style = KIconButtonStyle.plain,
    this.badge,
    this.dot = false,
    this.color,
  });

  final KIconData icon;
  final String label;
  final VoidCallback? onPressed;
  final KIconButtonStyle style;
  final int? badge;

  /// Small red dot (unread).
  final bool dot;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final (bg, border, circle) = switch (style) {
      KIconButtonStyle.plain => (Colors.transparent, null, false),
      KIconButtonStyle.soft => (c.soft, null, false),
      KIconButtonStyle.white => (
        Colors.white.withValues(alpha: .94),
        null,
        true,
      ),
      KIconButtonStyle.outline => (c.surface, c.line2, false),
    };
    final shape = circle
        ? const CircleBorder()
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KRadius.input),
            side: border == null ? BorderSide.none : BorderSide(color: border),
          );
    final hasBadge = badge != null && badge! > 0;
    return Semantics(
      button: true,
      // Callers fold the count into [label], e.g. "Cart, 3 items".
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: SizedBox.square(
        dimension: kMinTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (circle)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: k.shadow1,
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: Material(
                color: bg,
                shape: shape,
                elevation: 0,
                shadowColor: Colors.transparent,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  child: Center(child: KIcon(icon, color: color ?? c.ink)),
                ),
              ),
            ),
            if (dot)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: c.badFill,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            if (hasBadge) Positioned(top: 2, right: 0, child: KBadge(badge!)),
          ],
        ),
      ),
    );
  }
}
