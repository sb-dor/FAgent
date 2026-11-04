import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_completion.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';

/// {@template code_completion_list}
/// The completion list at the caret: a kind icon, the label and its type or signature per row,
/// the highlighted row tinted; a click inserts the row.
/// {@endtemplate}
class CodeCompletionList extends StatefulWidget {
  /// {@macro code_completion_list}
  const CodeCompletionList({
    required this.items,
    required this.highlighted,
    required this.onSelected,
    super.key,
  });

  /// The rows.
  final List<DartCompletion> items;

  /// The highlighted row.
  final int highlighted;

  /// Inserts a row.
  final ValueChanged<DartCompletion> onSelected;

  /// Width of the list.
  static const double width = 360;

  /// Height of a row.
  static const double rowHeight = 24;

  /// Rows shown before the list scrolls.
  static const int visibleRows = 8;

  /// Height of the list with [count] rows.
  static double heightFor(int count) => (count < visibleRows ? count : visibleRows) * rowHeight + 8;

  @override
  State<CodeCompletionList> createState() => _CodeCompletionListState();
}

class _CodeCompletionListState extends State<CodeCompletionList> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(CodeCompletionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keeps the highlighted row in view as ↑↓ move it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final top = widget.highlighted * CodeCompletionList.rowHeight;
      final view = _scroll.position.viewportDimension;
      if (top < _scroll.offset) {
        _scroll.jumpTo(top);
      } else if (top + CodeCompletionList.rowHeight > _scroll.offset + view) {
        _scroll.jumpTo(top + CodeCompletionList.rowHeight - view);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: BorderSide(color: colors.border),
      ),
      shadowColor: colors.shadow,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: CodeCompletionList.width,
        height: CodeCompletionList.heightFor(widget.items.length),
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemExtent: CodeCompletionList.rowHeight,
          itemCount: widget.items.length,
          itemBuilder: (context, index) => CodeCompletionRow(
            item: widget.items[index],
            highlighted: index == widget.highlighted,
            onTap: () => widget.onSelected(widget.items[index]),
          ),
        ),
      ),
    );
  }
}

/// {@template code_completion_row}
/// One row of [CodeCompletionList].
/// {@endtemplate}
class CodeCompletionRow extends StatelessWidget {
  /// {@macro code_completion_row}
  const CodeCompletionRow({
    required this.item,
    required this.highlighted,
    required this.onTap,
    super.key,
  });

  /// The completion.
  final DartCompletion item;

  /// Whether ↑↓ are on it.
  final bool highlighted;

  /// Inserts it.
  final VoidCallback onTap;

  static IconData _icon(DartCompletionKind kind) => switch (kind) {
    DartCompletionKind.classType => Icons.category_outlined,
    DartCompletionKind.method ||
    DartCompletionKind.function ||
    DartCompletionKind.constructor => Icons.functions,
    DartCompletionKind.field ||
    DartCompletionKind.property ||
    DartCompletionKind.variable => Icons.data_object,
    DartCompletionKind.keyword => Icons.key_outlined,
    DartCompletionKind.snippet => Icons.code,
    DartCompletionKind.enumType => Icons.list_alt,
    DartCompletionKind.module => Icons.inventory_2_outlined,
    DartCompletionKind.other => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: ColoredBox(
        color: highlighted ? colors.accentSoft : colors.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: <Widget>[
              Icon(_icon(item.kind), size: 14, color: colors.accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.mono(context, size: 12),
                ),
              ),
              if (item.detail case final detail?) ...<Widget>[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: AppText.mono(context, size: 11).copyWith(color: colors.muted),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
