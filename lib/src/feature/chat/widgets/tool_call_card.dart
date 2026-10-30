import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/utils/line_diff.dart';
import 'package:flutter_code_agent/src/common/widget/diff_view.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/diff_lines_cache.dart';
import 'package:flutter_code_agent/src/feature/chat/models/tool_row_label.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/expandable_row.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/tool_path_text.dart';

/// {@template tool_call_card}
/// A tool call as one compact row: icon, the agent's wording, the first touched file (name and
/// folder, relative to [projectRoot]), the `+N −M` counter for edits and the status. Expands to
/// diffs and output; edits start expanded, everything else collapsed.
/// {@endtemplate}
class ToolCallCard extends StatefulWidget {
  /// {@macro tool_call_card}
  const ToolCallCard({required this.call, this.projectRoot, this.onOpenChange, super.key});

  /// The tool call.
  final ToolCallItem call;

  /// The chat's project folder; paths inside it are shown relative to it.
  final String? projectRoot;

  /// Called with the first diff's path when the user clicks the row of an edit; with it the body
  /// opens with a separate chevron. `null`, or a call without diffs, keeps the whole header as the
  /// expander.
  final ValueChanged<String>? onOpenChange;

  /// Icon for an ACP tool [kind].
  static IconData toolIcon(String? kind) => switch (kind) {
    'read' => Icons.description_outlined,
    'edit' => Icons.edit_note,
    'delete' => Icons.delete_outline,
    'move' => Icons.drive_file_move_outline,
    'search' => Icons.search,
    'execute' => Icons.terminal,
    'think' => Icons.psychology_outlined,
    'fetch' => Icons.public,
    _ => Icons.build_outlined,
  };

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  static const int _maxOutputChars = 4000;

  final DiffLinesCache _diffLines = DiffLinesCache();

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final theme = Theme.of(context);
    final colors = context.colors;
    final diffs = call.diffs.toList();
    final lines = _diffLines.resolve(diffs);
    final texts = call.content.whereType<ToolTextContent>().toList();
    final output = call.rawOutput;
    final hasBody = diffs.isNotEmpty || texts.isNotEmpty || (output != null && output.isNotEmpty);
    final path = call.locations.isEmpty ? null : call.locations.first;
    final label = toolRowLabel(title: call.title, path: path, projectRoot: widget.projectRoot);
    final onOpenChange = widget.onOpenChange;
    return ExpandableRow(
      initiallyExpanded: diffs.isNotEmpty,
      onHeaderTap: onOpenChange == null || diffs.isEmpty
          ? null
          : () => onOpenChange(diffs.first.path),
      headerTooltip: Localization.of(context).openInChanges,
      header: Row(
        children: <Widget>[
          Icon(ToolCallCard.toolIcon(call.kind), size: 16, color: colors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: ToolPathText(
              label: label.title == null && label.name == null
                  ? ToolRowLabel(title: call.kind ?? 'tool')
                  : label,
            ),
          ),
          if (diffs.isNotEmpty) ...<Widget>[_DiffCounter(lines: lines), const SizedBox(width: 8)],
          _StatusIcon(status: call.status),
        ],
      ),
      body: !hasBody
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < diffs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DiffView(
                      path: diffs[i].path,
                      oldText: diffs[i].oldText,
                      newText: diffs[i].newText,
                      lines: lines[i],
                    ),
                  ),
                for (final text in texts)
                  SelectableText(text.text, style: theme.textTheme.bodySmall),
                if (output != null && output.isNotEmpty) ...<Widget>[
                  Text(Localization.of(context).toolOutput, style: theme.textTheme.labelSmall),
                  const SizedBox(height: 4),
                  SelectableText(
                    output.length > _maxOutputChars
                        ? '${output.substring(0, _maxOutputChars)}…'
                        : output,
                    style: AppText.mono(context),
                  ),
                ],
              ],
            ),
    );
  }
}

/// `+N −M` summed over all diffs of a call.
class _DiffCounter extends StatelessWidget {
  const _DiffCounter({required this.lines});

  final List<List<DiffLine>> lines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    var added = 0;
    var removed = 0;
    for (final diffLines in lines) {
      final stats = LineDiff.stats(diffLines);
      added += stats.added;
      removed += stats.removed;
    }
    final mono = AppText.mono(context);
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: '+$added',
            style: TextStyle(color: colors.ok),
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: '−$removed',
            style: TextStyle(color: colors.danger),
          ),
        ],
      ),
      style: mono,
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return switch (status) {
      'completed' => Icon(Icons.check_circle_outline, size: 16, color: colors.ok),
      'failed' => Icon(Icons.error_outline, size: 16, color: colors.danger),
      _ => const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 2)),
    };
  }
}
