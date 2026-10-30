import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

double _luminance(Color c) {
  double channel(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG contrast ratio between two colors.
double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('text is readable in both themes', () {
    for (final colors in [AppColors.light, AppColors.dark]) {
      expect(contrast(colors.text, colors.bg), greaterThanOrEqualTo(4.5));
      expect(contrast(colors.muted, colors.bg), greaterThanOrEqualTo(4.5));
      expect(contrast(colors.muted, colors.surface), greaterThanOrEqualTo(4.5));
    }
    expect(contrast(Colors.white, AppColors.light.accent), greaterThanOrEqualTo(4.5));
  });

  test('themes carry the tokens', () {
    expect(AppTheme.light().extension<AppColors>(), AppColors.light);
    expect(AppTheme.dark().extension<AppColors>(), AppColors.dark);
    expect(AppTheme.dark().colorScheme.primary, AppColors.dark.accent);
    expect(AppTheme.light().colorScheme.brightness, Brightness.light);
    expect(AppTheme.dark().colorScheme.brightness, Brightness.dark);
  });

  test('the themes are built once, so an equal theme is never a new one', () {
    expect(identical(AppTheme.light(), AppTheme.light()), isTrue);
    expect(identical(AppTheme.dark(), AppTheme.dark()), isTrue);
  });

  test('lerp halfway mixes colors', () {
    final mixed = AppColors.light.lerp(AppColors.dark, .5);
    expect(mixed.bg, Color.lerp(AppColors.light.bg, AppColors.dark.bg, .5));
  });
}
