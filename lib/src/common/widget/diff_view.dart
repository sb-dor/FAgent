import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/utils/line_diff.dart';
import 'package:path/path.dart' as p;

/// {@template diff_view}
/// A file change as a unified line diff, used by tool cards and permission
/// cards.
/// {@endtemplate}
class DiffView extends StatelessWidget {
  /// {@macro diff_view}
  const DiffView({
    required this.path,
    required this.newText,
    this.oldText,
    this.maxLines = 400,
    this.lines,
    super.key,
  });

  /// File path (shown relative to its folder name).
  final String path;

  /// Text before; `null` for a new file.
  final String? oldText;

  /// Text after.
  final String newText;

  /// Lines rendered before the rest is summarized.
  final int maxLines;

  /// The diff when the caller has already computed it (`LineDiff.compute`
  /// of [oldText] and [newText]); computed here otherwise.
  final List<DiffLine>? lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final lines = this.lines ?? LineDiff.compute(oldText, newText);
    final stats = LineDiff.stats(lines);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'Menlo', height: 1.35);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${p.basename(p.dirname(path))}/${p.basename(path)}',
                    style: mono?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (oldText == null)
                  Text(Localization.of(context).newFile, style: theme.textTheme.labelSmall)
                else ...<Widget>[
                  Text(
                    '+${stats.added}',
                    style: theme.textTheme.labelSmall?.copyWith(color: Colors.green.shade700),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '−${stats.removed}',
                    style: theme.textTheme.labelSmall?.copyWith(color: colors.error),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final line in lines.take(maxLines))
                    ColoredBox(
                      color: switch (line.kind) {
                        DiffLineKind.added => Colors.green.withValues(alpha: 0.14),
                        DiffLineKind.removed => colors.error.withValues(alpha: 0.12),
                        DiffLineKind.same => Colors.transparent,
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('$line', style: mono, softWrap: false),
                      ),
                    ),
                  if (lines.length > maxLines)
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text('… ${lines.length - maxLines}', style: mono),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
