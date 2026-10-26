import 'package:flutter/material.dart';

import '../icons/k_icon.dart';
import '../theme/k_theme.dart';
import '../theme/k_tokens.dart';

/// Count bubble: red for alerts, [blue] for neutral counts.
class KBadge extends StatelessWidget {
  const KBadge(this.count, {super.key, this.blue = false, this.ring = true});

  final int count;
  final bool blue;

  /// White outline so it reads on top of icons.
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    return ExcludeSemantics(
      child: Container(
        constraints: const BoxConstraints(minWidth: 18),
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: blue ? c.primary : c.badFill,
          borderRadius: BorderRadius.circular(9),
          boxShadow: ring
              ? const [BoxShadow(color: Colors.white, spreadRadius: 2)]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          count > 99 ? '99+' : '$count',
          style: context.k.text.caption.copyWith(
            fontSize: 11,
            height: 1,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Unread dot.
class KDot extends StatelessWidget {
  const KDot({super.key, this.size = 8});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: context.k.colors.primary,
      shape: BoxShape.circle,
    ),
  );
}

/// Ring spinner. White on filled buttons, [blue] on light surfaces.
class KSpinner extends StatelessWidget {
  const KSpinner({super.key, this.size = 18, this.blue = false});

  final double size;
  final bool blue;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    return SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: blue ? c.primary : Colors.white,
        backgroundColor: blue ? KColors.sky200 : Colors.white54,
      ),
    );
  }
}

/// Loading placeholder block.
class KSkeleton extends StatelessWidget {
  const KSkeleton({super.key, this.width, this.height = 12, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.k.colors.skeleton,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

enum KAvatarTone { sky, amber, green, violet, grey }

enum KAvatarSize { sm, md, lg }

/// Initials avatar.
class KAvatar extends StatelessWidget {
  const KAvatar(
    this.initials, {
    super.key,
    this.tone = KAvatarTone.sky,
    this.size = KAvatarSize.md,
  });

  final String initials;
  final KAvatarTone tone;
  final KAvatarSize size;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    final (bg, fg) = switch (tone) {
      KAvatarTone.sky => (c.tint2, c.primaryInk),
      KAvatarTone.amber => (const Color(0xFFFFEDD5), const Color(0xFF9A3412)),
      KAvatarTone.green => (const Color(0xFFDCFCE7), const Color(0xFF166534)),
      KAvatarTone.violet => (const Color(0xFFEDE9FE), const Color(0xFF5B21B6)),
      KAvatarTone.grey => (c.soft, c.ink3),
    };
    final (dim, font) = switch (size) {
      KAvatarSize.sm => (32.0, 12.0),
      KAvatarSize.md => (40.0, 14.0),
      KAvatarSize.lg => (64.0, 22.0),
    };
    return Container(
      width: dim,
      height: dim,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: context.k.text.body.copyWith(
          fontSize: font,
          height: 1,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

/// Section label used on cards and the gallery ("BUTTONS").
class KOverline extends StatelessWidget {
  const KOverline(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: context.k.text.overline);
}

/// Product picture placeholder tile (sample catalogue tints).
enum KArtTone { a, b, c, d, e, f, g }

class KProductArt extends StatelessWidget {
  const KProductArt({
    super.key,
    this.icon,
    this.image,
    this.tone = KArtTone.a,
    this.radius = KRadius.box,
  }) : assert(icon != null || image != null);

  /// Placeholder art from the product set in [KIcons].
  final KIconData? icon;

  /// The real product photo, when there is one. Covers the tile.
  final Widget? image;
  final KArtTone tone;
  final double radius;

  static (Color, Color) colorsFor(KArtTone tone) => switch (tone) {
    KArtTone.a => (const Color(0xFFE0F2FE), const Color(0xFF0369A1)),
    KArtTone.b => (const Color(0xFFEEF2F6), const Color(0xFF334155)),
    KArtTone.c => (const Color(0xFFFEF3C7), const Color(0xFF92400E)),
    KArtTone.d => (const Color(0xFFDCFCE7), const Color(0xFF166534)),
    KArtTone.e => (const Color(0xFFFCE7F3), const Color(0xFF9D174D)),
    KArtTone.f => (const Color(0xFFEDE9FE), const Color(0xFF5B21B6)),
    KArtTone.g => (const Color(0xFFFFEDD5), const Color(0xFF9A3412)),
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colorsFor(tone);
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ColoredBox(
          color: bg,
          child:
              image ??
              LayoutBuilder(
                builder: (context, box) => Center(
                  child: KIcon(
                    icon!,
                    size: box.maxWidth * 0.44,
                    color: fg,
                    strokeWidth: 1.15,
                  ),
                ),
              ),
        ),
      ),
    );
  }
}
