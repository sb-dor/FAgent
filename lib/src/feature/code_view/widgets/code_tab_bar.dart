import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_navigation_history.dart';
import 'package:path/path.dart' as p;

/// {@template code_tab_bar}
/// The open files of the Code view: the file name, ● while unsaved (✕ on hover), «Deleted» for a
/// file gone from disk, 🔒 for a read-only file; a click shows the file, ✕ or a middle click
/// closes it. ← and → at the right end walk the [history].
/// {@endtemplate}
class CodeTabBar extends StatelessWidget {
  /// {@macro code_tab_bar}
  const CodeTabBar({
    required this.tabs,
    required this.active,
    required this.labelFor,
    required this.history,
    required this.onBack,
    required this.onForward,
    required this.onActivate,
    required this.onClose,
    required this.onOpenExternally,
    super.key,
  });

  /// The open files in order.
  final List<CodeDocument> tabs;

  /// The shown file.
  final CodeDocument? active;

  /// The tab's tooltip: the path relative to the project, or `package:…` outside it.
  final String Function(CodeDocument document) labelFor;

  /// Where back and forward go.
  final CodeNavigationHistory history;

  /// Goes back.
  final VoidCallback onBack;

  /// Goes forward.
  final VoidCallback onForward;

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
        child: Row(
          children: <Widget>[
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  for (final tab in tabs)
                    _Tab(
                      document: tab,
                      active: identical(tab, active),
                      tooltip: labelFor(tab),
                      onActivate: () => onActivate(tab),
                      onClose: () => onClose(tab),
                      onOpenExternally: () => onOpenExternally(tab.path),
                    ),
                ],
              ),
            ),
            ListenableBuilder(
              listenable: history,
              builder: (context, _) {
                final localization = Localization.of(context);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _HistoryButton(
                      icon: Icons.arrow_back,
                      tooltip: localization.codeNavigateBack,
                      onPressed: history.canGoBack ? onBack : null,
                    ),
                    _HistoryButton(
                      icon: Icons.arrow_forward,
                      tooltip: localization.codeNavigateForward,
                      onPressed: history.canGoForward ? onForward : null,
                    ),
                    const SizedBox(width: 4),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryButton extends StatelessWidget {
  const _HistoryButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    icon: Icon(icon),
    iconSize: 16,
    color: context.colors.muted,
    disabledColor: context.colors.muted.withValues(alpha: 0.4),
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 26, height: 26),
    visualDensity: VisualDensity.compact,
    onPressed: onPressed,
  );
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
                    if (document.readOnly) ...<Widget>[
                      Tooltip(
                        message: Localization.of(context).codeReadOnly,
                        child: Icon(Icons.lock_outline, size: 14, color: colors.muted),
                      ),
                      const SizedBox(width: 4),
                    ],
                    ConstrainedBox(
                      // A read-only file shows its `package:` name, which can be long.
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        document.readOnly ? widget.tooltip : p.basename(document.path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: widget.active ? colors.text : colors.muted,
                          decoration: document.deleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (document.errorCount > 0) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(
                        'ⓧ ${document.errorCount}',
                        style: textTheme.labelSmall?.copyWith(color: colors.danger),
                      ),
                    ],
                    if (document.warningCount > 0) ...<Widget>[
                      const SizedBox(width: 4),
                      Text(
                        '⚠ ${document.warningCount}',
                        style: textTheme.labelSmall?.copyWith(color: colors.warn),
                      ),
                    ],
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
