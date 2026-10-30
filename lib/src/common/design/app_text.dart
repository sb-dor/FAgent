// ignore_for_file: avoid_classes_with_only_static_members

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';

/// Text styles that are not part of the Material `TextTheme`.
abstract final class AppText {
  /// Family name of the bundled JetBrains Mono font.
  static const String monoFamily = 'JetBrainsMono';

  /// Monospace style for code, paths and logs. Line height is 18/12.
  static TextStyle mono(BuildContext context, {double size = 12}) =>
      TextStyle(fontFamily: monoFamily, fontSize: size, height: 18 / 12, color: context.colors.text);
}
