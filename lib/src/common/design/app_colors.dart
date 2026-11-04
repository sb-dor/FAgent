import 'package:flutter/material.dart';

/// {@template app_colors}
/// Color tokens of the app. Two palettes: [light] and [dark].
///
/// Read them with `context.colors`.
/// {@endtemplate}
@immutable
final class AppColors extends ThemeExtension<AppColors> {
  /// {@macro app_colors}
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.ok,
    required this.okSoft,
    required this.warn,
    required this.warnSoft,
    required this.danger,
    required this.dangerSoft,
    required this.shadow,
    required this.syntaxKeyword,
    required this.syntaxType,
    required this.syntaxFunction,
    required this.syntaxString,
    required this.syntaxNumber,
    required this.syntaxComment,
    required this.syntaxMeta,
  });

  /// Light palette.
  static const AppColors light = AppColors(
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFF4F6F8),
    surfaceAlt: Color(0xFFFAFBFC),
    border: Color(0xFFE3E6EA),
    text: Color(0xFF1F2329),
    muted: Color(0xFF626A75),
    accent: Color(0xFF0175C2),
    accentSoft: Color(0xFFDCEEFB),
    onAccent: Color(0xFFFFFFFF),
    ok: Color(0xFF1E8E3E),
    okSoft: Color(0xFFE6F4EA),
    warn: Color(0xFFB26A00),
    warnSoft: Color(0xFFFFF4E0),
    danger: Color(0xFFD93025),
    dangerSoft: Color(0xFFFCE8E6),
    shadow: Color(0x1F000000),
    syntaxKeyword: Color(0xFFAF00DB),
    syntaxType: Color(0xFF267F99),
    syntaxFunction: Color(0xFF795E26),
    syntaxString: Color(0xFFA31515),
    syntaxNumber: Color(0xFF098658),
    syntaxComment: Color(0xFF008000),
    syntaxMeta: Color(0xFF001080),
  );

  /// Dark palette.
  static const AppColors dark = AppColors(
    bg: Color(0xFF16181B),
    surface: Color(0xFF1E2125),
    surfaceAlt: Color(0xFF1A1D20),
    border: Color(0xFF2E3238),
    text: Color(0xFFE6E8EB),
    muted: Color(0xFF8B939E),
    accent: Color(0xFF4FA8E8),
    accentSoft: Color(0xFF16344D),
    onAccent: Color(0xFF16181B),
    ok: Color(0xFF4CC26A),
    okSoft: Color(0xFF183424),
    warn: Color(0xFFE0A030),
    warnSoft: Color(0xFF3A2C12),
    danger: Color(0xFFF06A5F),
    dangerSoft: Color(0xFF3D1D1B),
    shadow: Color(0x66000000),
    syntaxKeyword: Color(0xFFC586C0),
    syntaxType: Color(0xFF4EC9B0),
    syntaxFunction: Color(0xFFDCDCAA),
    syntaxString: Color(0xFFCE9178),
    syntaxNumber: Color(0xFFB5CEA8),
    syntaxComment: Color(0xFF6A9955),
    syntaxMeta: Color(0xFF9CDCFE),
  );

  /// Feed and page background.
  final Color bg;

  /// Sidebar, header and page navigation.
  final Color surface;

  /// Right panel.
  final Color surfaceAlt;

  /// Dividers and outlines.
  final Color border;

  /// Primary text.
  final Color text;

  /// Captions and placeholders.
  final Color muted;

  /// Primary buttons and selection.
  final Color accent;

  /// Selected row and chip background.
  final Color accentSoft;

  /// Text and icons on a filled [accent] surface.
  final Color onAccent;

  /// Added lines, signed-in state.
  final Color ok;

  /// Background for [ok].
  final Color okSoft;

  /// Awaiting permission, Accept edits / Auto.
  final Color warn;

  /// Background for [warn].
  final Color warnSoft;

  /// Errors, Bypass, removed lines.
  final Color danger;

  /// Background for [danger].
  final Color dangerSoft;

  /// Drop shadow of popovers: black in both themes, stronger in dark.
  final Color shadow;

  /// Keywords (`class`, `final`, `if`) in the editor.
  final Color syntaxKeyword;

  /// Types and classes in the editor.
  final Color syntaxType;

  /// Function and method names in the editor.
  final Color syntaxFunction;

  /// String literals in the editor.
  final Color syntaxString;

  /// Numbers and literals (`true`, `null`) in the editor.
  final Color syntaxNumber;

  /// Comments in the editor.
  final Color syntaxComment;

  /// Annotations and other meta in the editor.
  final Color syntaxMeta;

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? text,
    Color? muted,
    Color? accent,
    Color? accentSoft,
    Color? onAccent,
    Color? ok,
    Color? okSoft,
    Color? warn,
    Color? warnSoft,
    Color? danger,
    Color? dangerSoft,
    Color? shadow,
    Color? syntaxKeyword,
    Color? syntaxType,
    Color? syntaxFunction,
    Color? syntaxString,
    Color? syntaxNumber,
    Color? syntaxComment,
    Color? syntaxMeta,
  }) => AppColors(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    border: border ?? this.border,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    accent: accent ?? this.accent,
    accentSoft: accentSoft ?? this.accentSoft,
    onAccent: onAccent ?? this.onAccent,
    ok: ok ?? this.ok,
    okSoft: okSoft ?? this.okSoft,
    warn: warn ?? this.warn,
    warnSoft: warnSoft ?? this.warnSoft,
    danger: danger ?? this.danger,
    dangerSoft: dangerSoft ?? this.dangerSoft,
    shadow: shadow ?? this.shadow,
    syntaxKeyword: syntaxKeyword ?? this.syntaxKeyword,
    syntaxType: syntaxType ?? this.syntaxType,
    syntaxFunction: syntaxFunction ?? this.syntaxFunction,
    syntaxString: syntaxString ?? this.syntaxString,
    syntaxNumber: syntaxNumber ?? this.syntaxNumber,
    syntaxComment: syntaxComment ?? this.syntaxComment,
    syntaxMeta: syntaxMeta ?? this.syntaxMeta,
  );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      ok: Color.lerp(ok, other.ok, t)!,
      okSoft: Color.lerp(okSoft, other.okSoft, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      warnSoft: Color.lerp(warnSoft, other.warnSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      syntaxKeyword: Color.lerp(syntaxKeyword, other.syntaxKeyword, t)!,
      syntaxType: Color.lerp(syntaxType, other.syntaxType, t)!,
      syntaxFunction: Color.lerp(syntaxFunction, other.syntaxFunction, t)!,
      syntaxString: Color.lerp(syntaxString, other.syntaxString, t)!,
      syntaxNumber: Color.lerp(syntaxNumber, other.syntaxNumber, t)!,
      syntaxComment: Color.lerp(syntaxComment, other.syntaxComment, t)!,
      syntaxMeta: Color.lerp(syntaxMeta, other.syntaxMeta, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppColors &&
          bg == other.bg &&
          surface == other.surface &&
          surfaceAlt == other.surfaceAlt &&
          border == other.border &&
          text == other.text &&
          muted == other.muted &&
          accent == other.accent &&
          accentSoft == other.accentSoft &&
          onAccent == other.onAccent &&
          ok == other.ok &&
          okSoft == other.okSoft &&
          warn == other.warn &&
          warnSoft == other.warnSoft &&
          danger == other.danger &&
          dangerSoft == other.dangerSoft &&
          shadow == other.shadow &&
          syntaxKeyword == other.syntaxKeyword &&
          syntaxType == other.syntaxType &&
          syntaxFunction == other.syntaxFunction &&
          syntaxString == other.syntaxString &&
          syntaxNumber == other.syntaxNumber &&
          syntaxComment == other.syntaxComment &&
          syntaxMeta == other.syntaxMeta;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    bg,
    surface,
    surfaceAlt,
    border,
    text,
    muted,
    accent,
    accentSoft,
    onAccent,
    ok,
    okSoft,
    warn,
    warnSoft,
    danger,
    dangerSoft,
    shadow,
    syntaxKeyword,
    syntaxType,
    syntaxFunction,
    syntaxString,
    syntaxNumber,
    syntaxComment,
    syntaxMeta,
  ]);
}

/// Access to [AppColors] from the nearest [Theme].
extension AppThemeContext on BuildContext {
  /// Color tokens of the current theme.
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
