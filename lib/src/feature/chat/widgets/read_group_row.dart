import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/expandable_row.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/tool_call_card.dart';

/// {@template read_group_row}
/// Consecutive file reads as one row: "Read N files" and the first path;
/// expands to the list of paths.
/// {@endtemplate}
class ReadGroupRow extends StatelessWidget {
  /// {@macro read_group_row}
  const ReadGroupRow({required this.calls, super.key});

  /// The grouped read calls.
  final List<ToolCallItem> calls;

  static String _path(ToolCallItem call) =>
      call.locations.isEmpty ? call.title : call.locations.first;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final mono = AppText.mono(context);
    final running = calls.any((c) => c.status != 'completed');
    return ExpandableRow(
      header: Row(
        children: <Widget>[
          Icon(ToolCallCard.toolIcon('read'), size: 16, color: colors.muted),
          const SizedBox(width: 8),
          Text(
            Localization.of(context).readFiles(calls.length),
            style: theme.textTheme.bodySmall?.copyWith(color: colors.text),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _path(calls.first),
              style: mono.copyWith(color: colors.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (running)
            const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(Icons.check_circle_outline, size: 16, color: colors.ok),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final call in calls)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText(_path(call), style: mono.copyWith(color: colors.muted)),
            ),
        ],
      ),
    );
  }
}
