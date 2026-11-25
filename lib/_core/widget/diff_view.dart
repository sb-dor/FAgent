import 'package:flutter_code_agent/_core/design/app_colors.dart';
import 'package:flutter_code_agent/_core/design/app_theme.dart';
import 'package:flutter_code_agent/_core/localization/localization.dart';
import 'package:flutter_code_agent/_core/utils/line_diff.dart';
import 'package:material_ui/material_ui.dart';
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

  /// The diff of [oldText] and [newText], computed by the caller; `null`
  /// while it is still being computed (a placeholder is shown).
  final List<DiffLine>? lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final lines = this.lines;
    final stats = lines == null ? null : LineDiff.stats(lines);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'Menlo', height: 1.35);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(AppRadius.medium),
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
                if (stats == null)
                  const SizedBox.shrink()
                else if (oldText == null)
                  Text(Localization.of(context).newFile, style: theme.textTheme.labelSmall)
                else ...<Widget>[
                  Text(
                    '+${stats.added}',
                    style: theme.textTheme.labelSmall?.copyWith(color: colors.ok),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '−${stats.removed}',
                    style: theme.textTheme.labelSmall?.copyWith(color: colors.danger),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          if (lines == null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                Localization.of(context).diffComputing,
                style: mono?.copyWith(color: colors.muted),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final line in lines.take(maxLines))
                      ColoredBox(
                        color: switch (line.kind) {
                          DiffLineKind.added => colors.okSoft,
                          DiffLineKind.removed => colors.dangerSoft,
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
