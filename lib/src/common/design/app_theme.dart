// ignore_for_file: avoid_classes_with_only_static_members

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';

/// Corner radii of the design system.
abstract final class AppRadius {
  /// Tags and small buttons.
  static const double small = 6;

  /// Cards and fields.
  static const double medium = 10;

  /// Composer and dialogs.
  static const double large = 14;
}

/// Light and dark [ThemeData] built from [AppColors].
abstract final class AppTheme {
  /// Light theme.
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  /// Dark theme.
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(seedColor: c.accent, brightness: brightness).copyWith(
      primary: c.accent,
      onPrimary: isLight ? Colors.white : c.bg,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.text,
      surface: c.bg,
      onSurface: c.text,
      onSurfaceVariant: c.muted,
      surfaceContainerLowest: c.bg,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceAlt,
      surfaceContainerHighest: c.surface,
      outline: c.muted,
      outlineVariant: c.border,
      error: c.danger,
      onError: isLight ? Colors.white : c.bg,
      errorContainer: c.dangerSoft,
      onErrorContainer: c.danger,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      dividerColor: c.border,
      extensions: <ThemeExtension<dynamic>>[c],
      textTheme: TextTheme(
        bodyMedium: TextStyle(fontSize: 13, height: 20 / 13, color: c.text),
        bodySmall: TextStyle(fontSize: 12, height: 16 / 12, color: c.muted),
        titleSmall: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.text),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.accent : c.border,
        ),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.text, borderRadius: BorderRadius.circular(AppRadius.small)),
        textStyle: TextStyle(fontSize: 12, height: 16 / 12, color: c.bg),
      ),
    );
  }
}
