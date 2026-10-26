import 'package:flutter/material.dart';

import 'k_theme.dart';
import 'k_tokens.dart';
import 'k_typography.dart';

/// Material theme built from the K tokens, so stock Material widgets look
/// right too. K widgets read [KTheme] directly.
abstract final class AppTheme {
  static ThemeData light() {
    final k = KTheme.light;
    final c = k.colors;
    final t = k.text;
    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: c.primary,
      onPrimary: Colors.white,
      primaryContainer: c.tint2,
      onPrimaryContainer: c.primaryInk,
      secondary: c.primaryInk,
      onSecondary: Colors.white,
      secondaryContainer: c.tint,
      onSecondaryContainer: c.primaryInk,
      error: c.bad,
      onError: Colors.white,
      errorContainer: c.badBg,
      onErrorContainer: c.bad,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.ink3,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.bg,
      surfaceContainer: c.bg,
      surfaceContainerHigh: c.soft,
      surfaceContainerHighest: c.soft,
      outline: c.line2,
      outlineVariant: c.line,
      shadow: c.ink,
      scrim: c.ink,
      inverseSurface: c.ink,
      onInverseSurface: Colors.white,
      inversePrimary: KColors.sky300,
    );
    final textTheme = TextTheme(
      displaySmall: t.display,
      headlineMedium: t.h1,
      headlineSmall: t.h2,
      titleLarge: t.h3,
      titleMedium: t.h3.copyWith(fontSize: 15, height: 22 / 15),
      titleSmall: t.label.copyWith(color: c.ink),
      bodyLarge: t.body,
      bodyMedium: t.body,
      bodySmall: t.small,
      labelLarge: t.button,
      labelMedium: t.label,
      labelSmall: t.caption,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KRadius.input),
    );
    const buttonSize = Size(kMinTap, 48);

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(KRadius.input),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: KFonts.family,
      fontFamilyFallback: KFonts.fallback,
      textTheme: textTheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.surface,
      dividerColor: c.line,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: InkSparkle.splashFactory,
      extensions: [k],
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 56,
        titleTextStyle: t.h3,
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: c.line,
          disabledForegroundColor: c.muted,
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: t.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          backgroundColor: c.surface,
          side: BorderSide(color: c.line2),
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: t.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          minimumSize: const Size(kMinTap, kMinTap),
          shape: buttonShape,
          textStyle: t.button,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        hintStyle: t.body.copyWith(color: c.muted),
        labelStyle: t.label,
        helperStyle: t.caption.copyWith(color: c.muted),
        errorStyle: t.caption.copyWith(
          color: c.bad,
          fontWeight: FontWeight.w600,
        ),
        border: border(c.line2),
        enabledBorder: border(c.line2),
        focusedBorder: border(c.primary),
        errorBorder: border(c.bad),
        focusedErrorBorder: border(c.bad),
        disabledBorder: border(c.line2),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.tint2,
        side: BorderSide(color: c.line2),
        shape: const StadiumBorder(),
        labelStyle: t.label,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: KColors.scrim,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(KRadius.sheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        barrierColor: KColors.scrim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KRadius.dialog),
        ),
        titleTextStyle: t.title,
        contentTextStyle: t.small.copyWith(
          fontSize: 14,
          height: 21 / 14,
          color: c.ink2,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.ink,
        contentTextStyle: t.small.copyWith(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: KColors.sky300,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KRadius.box),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.line,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primary : c.line2,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primary : null,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primary : c.line2,
        ),
      ),
    );
  }
}
