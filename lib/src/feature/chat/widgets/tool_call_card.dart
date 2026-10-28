import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/diff_view.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';

/// {@template tool_call_card}
/// A tool call with its status; expands to diffs and output. Edits start
/// expanded, everything else collapsed.
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
    final title = Row(
      children: <Widget>[
        Icon(_icon(call.kind), size: 18, color: colors.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            call.title.isEmpty ? (call.kind ?? 'tool') : call.title,
            style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'Menlo'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        _StatusIcon(status: call.status),
      ],
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.border),
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: !hasBody
          ? Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: title)
          : Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: diffs.isNotEmpty,
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                title: title,
                children: <Widget>[
                  for (final diff in diffs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DiffView(
                        path: diff.path,
                        oldText: diff.oldText,
                        newText: diff.newText,
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
                      style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'Menlo'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  static IconData _icon(String? kind) => switch (kind) {
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

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return switch (status) {
      'completed' => Icon(Icons.check_circle_outline, size: 18, color: colors.ok),
      'failed' => Icon(Icons.error_outline, size: 18, color: colors.danger),
      _ => const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
    };
  }
}
