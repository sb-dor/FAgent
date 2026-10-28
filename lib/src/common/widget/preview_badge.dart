import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';

/// {@template preview_badge}
/// A small "Preview" pill that marks a screen or feature as not final.
/// {@endtemplate}
class PreviewBadge extends StatelessWidget {
  /// {@macro preview_badge}
  const PreviewBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.accent, fontWeight: FontWeight.w600);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(Localization.of(context).preview, style: style),
      ),
    );
  }
}
