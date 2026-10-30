import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/utils/line_diff.dart';
import 'package:flutter_code_agent/src/common/widget/diff_view.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/expandable_row.dart';

/// {@template tool_call_card}
/// A tool call as one compact row: icon, title, the first touched path, the
/// `+N −M` counter for edits and the status. Expands to diffs and output;
/// edits start expanded, everything else collapsed.
/// {@endtemplate}
class ToolCallCard extends StatelessWidget {
  /// {@macro tool_call_card}
  const ToolCallCard({required this.call, super.key});

  /// The tool call.
  final ToolCallItem call;

  static const int _maxOutputChars = 4000;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final diffs = call.diffs.toList();
    final texts = call.content.whereType<ToolTextContent>().toList();
    final output = call.rawOutput;
    final hasBody = diffs.isNotEmpty || texts.isNotEmpty || (output != null && output.isNotEmpty);
    final mono = AppText.mono(context).copyWith(color: colors.muted);
    final path = call.locations.isEmpty ? null : call.locations.first;
    return ExpandableRow(
      initiallyExpanded: diffs.isNotEmpty,
      header: Row(
        children: <Widget>[
          Icon(toolIcon(call.kind), size: 16, color: colors.muted),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: Text(
              call.title.isEmpty ? (call.kind ?? 'tool') : call.title,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (path != null) ...<Widget>[
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Text(path, style: mono, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
          const Spacer(),
          if (diffs.isNotEmpty) ...<Widget>[_DiffCounter(diffs: diffs), const SizedBox(width: 8)],
          _StatusIcon(status: call.status),
        ],
      ),
      body: !hasBody
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final diff in diffs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DiffView(path: diff.path, oldText: diff.oldText, newText: diff.newText),
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
}

/// `+N −M` summed over all diffs of a call.
class _DiffCounter extends StatelessWidget {
  const _DiffCounter({required this.diffs});

  final List<ToolDiffContent> diffs;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    var added = 0;
    var removed = 0;
    for (final diff in diffs) {
      final stats = LineDiff.stats(LineDiff.compute(diff.oldText, diff.newText));
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
