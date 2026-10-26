import 'package:flutter/painting.dart';

import 'k_tokens.dart';

/// Plus Jakarta Sans, with Kantumruy Pro picked up glyph-by-glyph for Khmer.
abstract final class KFonts {
  static const family = 'PlusJakartaSans';
  static const khmer = 'KantumruyPro';
  static const fallback = [khmer];
}

TextStyle _style(
  double size,
  double lineHeight,
  FontWeight weight, {
  double letterSpacing = 0,
  Color color = KColors.ink,
}) => TextStyle(
  fontFamily: KFonts.family,
  fontFamilyFallback: KFonts.fallback,
  fontSize: size,
  height: lineHeight / size,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  color: color,
  leadingDistribution: TextLeadingDistribution.even,
);

/// The K type scale (size/line height/weight from the Brand board).
abstract final class KTextStyles {
  static final display = _style(32, 40, FontWeight.w800, letterSpacing: -0.64);
  static final h1 = _style(24, 32, FontWeight.w800, letterSpacing: -0.36);
  static final h2 = _style(20, 28, FontWeight.w700, letterSpacing: -0.2);
  static final h3 = _style(17, 24, FontWeight.w700);
  static final body = _style(15, 22, FontWeight.w400);
  static final label = _style(13, 18, FontWeight.w600, color: KColors.ink2);
  static final small = _style(13, 18, FontWeight.w400);
  static final caption = _style(12, 16, FontWeight.w500);
  static final overline = _style(
    12,
    16,
    FontWeight.w700,
    letterSpacing: 0.72,
    color: KColors.muted,
  );
  static final price = _style(
    24,
    32,
    FontWeight.w800,
    letterSpacing: -0.24,
  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// Sheet and dialog titles (19/26/800).
  static final title = _style(19, 26, FontWeight.w800);

  /// Buttons and tabs.
  static final button = _style(15, 20, FontWeight.w700);
}
