import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:path/path.dart' as p;

/// {@template code_tab_bar}
/// The open files of the Code view: the file name, ● while unsaved (✕ on hover), «Deleted» for a
/// file gone from disk; a click shows the file, ✕ or a middle click closes it.
/// {@endtemplate}
class CodeTabBar extends StatelessWidget {
  /// {@macro code_tab_bar}
  const CodeTabBar({
    required this.tabs,
    required this.active,
    required this.root,
    required this.onActivate,
    required this.onClose,
    required this.onOpenExternally,
    super.key,
  });

  /// The open files in order.
  final List<CodeDocument> tabs;

  /// The shown file.
  final CodeDocument? active;

  /// The project's folder, for the relative path in the tooltip.
  final String root;

  /// Shows a file.
  final ValueChanged<CodeDocument> onActivate;

  /// Asks to close a file.
  final ValueChanged<CodeDocument> onClose;

  /// Opens a file in the system's default app.
  final ValueChanged<String> onOpenExternally;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: <Widget>[
            for (final tab in tabs)
              _Tab(
                document: tab,
                active: identical(tab, active),
                tooltip: p.relative(tab.path, from: root),
                onActivate: () => onActivate(tab),
                onClose: () => onClose(tab),
                onOpenExternally: () => onOpenExternally(tab.path),
              ),
          ],
        ),
      ),
    );
  }
}

enum _TabAction { close, openExternally }

class _Tab extends StatefulWidget {
  const _Tab({
    required this.document,
    required this.active,
    required this.tooltip,
    required this.onActivate,
    required this.onClose,
    required this.onOpenExternally,
  });

  final CodeDocument document;
  final bool active;
  final String tooltip;
  final VoidCallback onActivate;
  final VoidCallback onClose;
  final VoidCallback onOpenExternally;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hovered = false;

  Future<void> _menu(Offset position) async {
    final localization = Localization.of(context);
    final action = await showAppMenu<_TabAction>(
      context: context,
      anchor: Rect.fromLTWH(position.dx, position.dy, 0, 0),
      width: 260,
      sections: <AppMenuSection<_TabAction>>[
        AppMenuSection<_TabAction>(
          items: <AppMenuItem<_TabAction>>[
            AppMenuItem<_TabAction>(value: _TabAction.close, title: localization.close),
            AppMenuItem<_TabAction>(
              value: _TabAction.openExternally,
              title: localization.codeOpenExternally,
              icon: Icons.open_in_new,
            ),
          ],
        ),
      ],
    );
    switch (action) {
      case _TabAction.close:
        widget.onClose();
      case _TabAction.openExternally:
        widget.onOpenExternally();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final document = widget.document;
    final textTheme = Theme.of(context).textTheme;
    final close = SizedBox(
      width: 18,
      height: 18,
      child: document.dirty && !_hovered
          ? Center(
              child: Text('●', style: textTheme.bodySmall?.copyWith(color: colors.text)),
            )
          : InkWell(
              onTap: widget.onClose,
              borderRadius: BorderRadius.circular(AppRadius.small),
              child: Icon(
                Icons.close,
                size: 14,
                color: _hovered || widget.active ? colors.muted : colors.muted.withValues(alpha: 0),
              ),
            ),
    );
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kMiddleMouseButton) widget.onClose();
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Tooltip(
          message: widget.tooltip,
          waitDuration: const Duration(milliseconds: 600),
          child: InkWell(
            onTap: widget.onActivate,
            onSecondaryTapUp: (details) => _menu(details.globalPosition),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.active ? colors.bg : colors.surface,
                border: Border(
                  right: BorderSide(color: colors.border),
                  bottom: BorderSide(
                    color: widget.active ? colors.accent : colors.border.withValues(alpha: 0),
                    width: 2,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      p.basename(document.path),
                      style: textTheme.bodySmall?.copyWith(
                        color: widget.active ? colors.text : colors.muted,
                        decoration: document.deleted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (document.deleted) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(
                        Localization.of(context).codeDeleted,
                        style: textTheme.labelSmall?.copyWith(color: colors.danger),
                      ),
                    ],
                    const SizedBox(width: 6),
                    close,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
