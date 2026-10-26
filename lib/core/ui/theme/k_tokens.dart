import 'package:flutter/painting.dart';

/// Raw K design tokens, mirrored from `delivery/K_UX-UI_Screens/k-ui.css`.
/// Widgets read them through [KTheme] (`context.k`) so a future dark theme
/// only swaps the palette.
abstract final class KColors {
  static const sky50 = Color(0xFFF0F9FF);
  static const sky100 = Color(0xFFE0F2FE);
  static const sky200 = Color(0xFFBAE6FD);
  static const sky300 = Color(0xFF7DD3FC);
  static const sky400 = Color(0xFF38BDF8);

  /// Brand sky — logo, illustration, decoration. Never text.
  static const sky500 = Color(0xFF0EA5E9);
  static const sky900 = Color(0xFF0C4A6E);

  /// Buttons, links, active states (5.1:1 on white).
  static const primary = Color(0xFF0272B6);
  static const primaryPress = Color(0xFF025A91);

  /// Text on sky tints.
  static const primaryInk = Color(0xFF025A91);

  static const ink = Color(0xFF0F172A);
  static const ink2 = Color(0xFF334155);
  static const ink3 = Color(0xFF475569);

  /// Captions on white / background only.
  static const muted = Color(0xFF64748B);
  static const line = Color(0xFFE2E8F0);
  static const line2 = Color(0xFFCBD5E1);

  static const bg = Color(0xFFF8FAFC);
  static const surface = Color(0xFFFFFFFF);
  static const soft = Color(0xFFF1F5F9);
  static const skeleton = Color(0xFFEDF1F6);

  static const ok = Color(0xFF047857);
  static const okBg = Color(0xFFECFDF5);
  static const okLine = Color(0xFFA7F3D0);
  static const okText = Color(0xFF064E3B);
  static const warn = Color(0xFFB45309);
  static const warnBg = Color(0xFFFFF7ED);
  static const warnLine = Color(0xFFFED7AA);
  static const warnText = Color(0xFF7C2D12);
  static const bad = Color(0xFFB91C1C);
  static const badBg = Color(0xFFFEF2F2);
  static const badLine = Color(0xFFFECACA);
  static const badText = Color(0xFF7F1D1D);

  /// Destructive buttons.
  static const badFill = Color(0xFFDC2626);
  static const star = Color(0xFFF59E0B);
  static const heart = Color(0xFFE11D48);
  static const violet = Color(0xFF6D28D9);
  static const violetBg = Color(0xFFF5F3FF);

  /// Toast accents on the ink background.
  static const toastOk = Color(0xFF6EE7B7);
  static const toastBad = Color(0xFFFCA5A5);

  static const scrim = Color(0x800F172A);
}

/// 8-pt rhythm with a 4 px half-step.
abstract final class KSpacing {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x12 = 48;

  /// Screen gutter and card padding.
  static const double gutter = 16;
}

abstract final class KRadius {
  static const double tag = 8;
  static const double buttonSm = 10;
  static const double input = 12;
  static const double box = 14;
  static const double card = 16;
  static const double dialog = 22;
  static const double sheet = 24;
  static const double pill = 999;
}

/// Borders first; shadows only for things that float.
abstract final class KShadows {
  static const level1 = [
    BoxShadow(color: Color(0x0D0F172A), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x120F172A), offset: Offset(0, 1), blurRadius: 3),
  ];
  static const level2 = [
    BoxShadow(color: Color(0x140F172A), offset: Offset(0, 8), blurRadius: 24),
  ];
  static const level3 = [
    BoxShadow(color: Color(0x380F172A), offset: Offset(0, 18), blurRadius: 48),
  ];
}

/// Minimum touch target.
const double kMinTap = 44;
