import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/dart_analysis_repository.dart';

/// {@template code_analysis_footer}
/// Under a Dart file: «Analyzing…» while the analysis starts or works, a line with **Restart**
/// when it is unavailable, nothing when it is ready.
/// {@endtemplate}
class CodeAnalysisFooter extends StatelessWidget {
  /// {@macro code_analysis_footer}
  const CodeAnalysisFooter({required this.status, required this.onRestart, super.key});

  /// What the analysis does.
  final ValueListenable<DartAnalysisStatus> status;

  /// Starts the analysis again.
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DartAnalysisStatus>(
    valueListenable: status,
    builder: (context, status, _) {
      final colors = context.colors;
      final localization = Localization.of(context);
      final textTheme = Theme.of(context).textTheme;
      final content = switch (status) {
        DartAnalysis$StartingState() || DartAnalysis$AnalyzingState() => Row(
          children: <Widget>[
            SizedBox.square(
              dimension: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: colors.muted),
            ),
            const SizedBox(width: 8),
            Text(
              localization.codeAnalyzing,
              style: textTheme.labelSmall?.copyWith(color: colors.muted),
            ),
          ],
        ),
        DartAnalysis$UnavailableState(:final reason) => Row(
          children: <Widget>[
            Icon(Icons.error_outline, size: 14, color: colors.warn),
            const SizedBox(width: 6),
            Text(
              localization.codeAnalysisUnavailable,
              style: textTheme.labelSmall?.copyWith(color: colors.text),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                reason,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(color: colors.muted),
              ),
            ),
            TextButton(
              onPressed: onRestart,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(localization.codeAnalysisRestart),
            ),
          ],
        ),
        DartAnalysis$IdleState() || DartAnalysis$ReadyState() => null,
      };
      if (content == null) return const SizedBox.shrink();
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: SizedBox(
          height: 28,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: content),
        ),
      );
    },
  );
}
