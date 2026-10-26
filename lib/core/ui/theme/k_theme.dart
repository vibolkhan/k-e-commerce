import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'k_tokens.dart';
import 'k_typography.dart';

/// Semantic colours the K widgets paint with. Only a light palette exists
/// today; a dark one plugs in here.
@immutable
class KPalette {
  const KPalette({
    required this.primary,
    required this.primaryPress,
    required this.primaryInk,
    required this.brand,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.muted,
    required this.line,
    required this.line2,
    required this.bg,
    required this.surface,
    required this.soft,
    required this.skeleton,
    required this.tint,
    required this.tint2,
    required this.tintLine,
    required this.ok,
    required this.okBg,
    required this.warn,
    required this.warnBg,
    required this.bad,
    required this.badBg,
    required this.badFill,
    required this.violet,
    required this.violetBg,
    required this.star,
  });

  static const light = KPalette(
    primary: KColors.primary,
    primaryPress: KColors.primaryPress,
    primaryInk: KColors.primaryInk,
    brand: KColors.sky500,
    ink: KColors.ink,
    ink2: KColors.ink2,
    ink3: KColors.ink3,
    muted: KColors.muted,
    line: KColors.line,
    line2: KColors.line2,
    bg: KColors.bg,
    surface: KColors.surface,
    soft: KColors.soft,
    skeleton: KColors.skeleton,
    tint: KColors.sky50,
    tint2: KColors.sky100,
    tintLine: KColors.sky300,
    ok: KColors.ok,
    okBg: KColors.okBg,
    warn: KColors.warn,
    warnBg: KColors.warnBg,
    bad: KColors.bad,
    badBg: KColors.badBg,
    badFill: KColors.badFill,
    violet: KColors.violet,
    violetBg: KColors.violetBg,
    star: KColors.star,
  );

  final Color primary;
  final Color primaryPress;
  final Color primaryInk;
  final Color brand;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color muted;
  final Color line;
  final Color line2;
  final Color bg;
  final Color surface;
  final Color soft;
  final Color skeleton;

  /// Sky 50 / 100 / 300 — selected and informational surfaces.
  final Color tint;
  final Color tint2;
  final Color tintLine;
  final Color ok;
  final Color okBg;
  final Color warn;
  final Color warnBg;
  final Color bad;
  final Color badBg;
  final Color badFill;
  final Color violet;
  final Color violetBg;
  final Color star;

  List<Color> get _all => [
    primary,
    primaryPress,
    primaryInk,
    brand,
    ink,
    ink2,
    ink3,
    muted,
    line,
    line2,
    bg,
    surface,
    soft,
    skeleton,
    tint,
    tint2,
    tintLine,
    ok,
    okBg,
    warn,
    warnBg,
    bad,
    badBg,
    badFill,
    violet,
    violetBg,
    star,
  ];

  static KPalette _fromList(List<Color> c) => KPalette(
    primary: c[0],
    primaryPress: c[1],
    primaryInk: c[2],
    brand: c[3],
    ink: c[4],
    ink2: c[5],
    ink3: c[6],
    muted: c[7],
    line: c[8],
    line2: c[9],
    bg: c[10],
    surface: c[11],
    soft: c[12],
    skeleton: c[13],
    tint: c[14],
    tint2: c[15],
    tintLine: c[16],
    ok: c[17],
    okBg: c[18],
    warn: c[19],
    warnBg: c[20],
    bad: c[21],
    badBg: c[22],
    badFill: c[23],
    violet: c[24],
    violetBg: c[25],
    star: c[26],
  );

  static KPalette lerp(KPalette a, KPalette b, double t) {
    final from = a._all;
    final to = b._all;
    return _fromList([
      for (var i = 0; i < from.length; i++) Color.lerp(from[i], to[i], t)!,
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is KPalette && listEquals(other._all, _all);

  @override
  int get hashCode => Object.hashAll(_all);
}

/// The K type scale as a theme value.
@immutable
class KTextTheme {
  KTextTheme({
    TextStyle? display,
    TextStyle? h1,
    TextStyle? h2,
    TextStyle? h3,
    TextStyle? body,
    TextStyle? label,
    TextStyle? small,
    TextStyle? caption,
    TextStyle? overline,
    TextStyle? price,
    TextStyle? title,
    TextStyle? button,
  }) : display = display ?? KTextStyles.display,
       h1 = h1 ?? KTextStyles.h1,
       h2 = h2 ?? KTextStyles.h2,
       h3 = h3 ?? KTextStyles.h3,
       body = body ?? KTextStyles.body,
       label = label ?? KTextStyles.label,
       small = small ?? KTextStyles.small,
       caption = caption ?? KTextStyles.caption,
       overline = overline ?? KTextStyles.overline,
       price = price ?? KTextStyles.price,
       title = title ?? KTextStyles.title,
       button = button ?? KTextStyles.button;

  final TextStyle display;
  final TextStyle h1;
  final TextStyle h2;
  final TextStyle h3;
  final TextStyle body;
  final TextStyle label;
  final TextStyle small;
  final TextStyle caption;
  final TextStyle overline;
  final TextStyle price;
  final TextStyle title;
  final TextStyle button;

  static KTextTheme lerp(KTextTheme a, KTextTheme b, double t) => KTextTheme(
    display: TextStyle.lerp(a.display, b.display, t),
    h1: TextStyle.lerp(a.h1, b.h1, t),
    h2: TextStyle.lerp(a.h2, b.h2, t),
    h3: TextStyle.lerp(a.h3, b.h3, t),
    body: TextStyle.lerp(a.body, b.body, t),
    label: TextStyle.lerp(a.label, b.label, t),
    small: TextStyle.lerp(a.small, b.small, t),
    caption: TextStyle.lerp(a.caption, b.caption, t),
    overline: TextStyle.lerp(a.overline, b.overline, t),
    price: TextStyle.lerp(a.price, b.price, t),
    title: TextStyle.lerp(a.title, b.title, t),
    button: TextStyle.lerp(a.button, b.button, t),
  );
}

/// K tokens on [ThemeData]. Read with `context.k`.
@immutable
class KTheme extends ThemeExtension<KTheme> {
  const KTheme({
    required this.colors,
    required this.text,
    this.shadow1 = KShadows.level1,
    this.shadow2 = KShadows.level2,
    this.shadow3 = KShadows.level3,
  });

  static final light = KTheme(colors: KPalette.light, text: KTextTheme());

  final KPalette colors;
  final KTextTheme text;
  final List<BoxShadow> shadow1;
  final List<BoxShadow> shadow2;
  final List<BoxShadow> shadow3;

  @override
  KTheme copyWith({
    KPalette? colors,
    KTextTheme? text,
    List<BoxShadow>? shadow1,
    List<BoxShadow>? shadow2,
    List<BoxShadow>? shadow3,
  }) => KTheme(
    colors: colors ?? this.colors,
    text: text ?? this.text,
    shadow1: shadow1 ?? this.shadow1,
    shadow2: shadow2 ?? this.shadow2,
    shadow3: shadow3 ?? this.shadow3,
  );

  @override
  KTheme lerp(KTheme? other, double t) {
    if (other == null) return this;
    return KTheme(
      colors: KPalette.lerp(colors, other.colors, t),
      text: KTextTheme.lerp(text, other.text, t),
      shadow1: BoxShadow.lerpList(shadow1, other.shadow1, t)!,
      shadow2: BoxShadow.lerpList(shadow2, other.shadow2, t)!,
      shadow3: BoxShadow.lerpList(shadow3, other.shadow3, t)!,
    );
  }
}

extension KThemeContext on BuildContext {
  /// The K theme; falls back to light when a test pumps without [AppTheme].
  KTheme get k => Theme.of(this).extension<KTheme>() ?? KTheme.light;
}
