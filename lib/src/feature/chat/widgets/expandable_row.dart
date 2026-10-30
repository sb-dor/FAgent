import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';

/// {@template expandable_row}
/// A compact feed row: a [header] line that toggles an optional [body] below
/// it. Without a [body] the row is not interactive.
/// {@endtemplate}
class ExpandableRow extends StatefulWidget {
  /// {@macro expandable_row}
  const ExpandableRow({
    required this.header,
    this.body,
    this.initiallyExpanded = false,
    this.bordered = true,
    super.key,
  });

  /// The always visible line.
  final Widget header;

  /// What opens on tap; `null` when there is nothing more to show.
  final Widget? body;

  /// Whether the body starts open.
  final bool initiallyExpanded;

  /// Draws the `surface` card with a border around the row (tool rows), or
  /// leaves it plain (thinking).
  final bool bordered;

  @override
  State<ExpandableRow> createState() => _ExpandableRowState();
}

class _ExpandableRowState extends State<ExpandableRow> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final body = widget.body;
    final padding = widget.bordered
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
        : const EdgeInsets.symmetric(vertical: 4);
    final header = Padding(padding: padding, child: widget.header);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (body == null) header else InkWell(onTap: _toggle, child: header),
        if (body != null && _expanded)
          Padding(
            padding: EdgeInsets.fromLTRB(widget.bordered ? 12 : 0, 0, widget.bordered ? 12 : 0, 12),
            child: body,
          ),
      ],
    );
    if (!widget.bordered) return column;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Material(type: MaterialType.transparency, child: column),
      ),
    );
  }

  void _toggle() => setState(() => _expanded = !_expanded);
}
