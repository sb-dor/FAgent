import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';

/// {@template chat_drop_target}
/// Takes files dragged onto the whole chat: while they hover the chat is dimmed with "Release to
/// attach", and the dropped paths go to [onDropped] in drop order.
///
/// A chat that is hidden (another page of the workspace is shown) or under a dialog takes no
/// drop: the platform reports a drag to every target, seen or not.
/// {@endtemplate}
class ChatDropTarget extends StatefulWidget {
  /// {@macro chat_drop_target}
  const ChatDropTarget({required this.onDropped, required this.child, super.key});

  /// Called with the absolute paths of the dropped files and folders.
  final ValueChanged<List<String>> onDropped;

  /// The chat.
  final Widget child;

  @override
  State<ChatDropTarget> createState() => _ChatDropTargetState();
}

class _ChatDropTargetState extends State<ChatDropTarget> {
  bool _hovering = false;

  void _setHovering(bool hovering) {
    if (_hovering != hovering) setState(() => _hovering = hovering);
  }

  void _onDone(DropDoneDetails details) {
    _setHovering(false);
    final paths = <String>[
      for (final file in details.files)
        if (file.path.isNotEmpty) file.path,
    ];
    if (paths.isNotEmpty) widget.onDropped(paths);
  }

  @override
  Widget build(BuildContext context) {
    // The workspace hides the chat with Offstage and a disabled TickerMode.
    final enabled =
        TickerMode.valuesOf(context).enabled && (ModalRoute.isCurrentOf(context) ?? true);
    final colors = context.colors;
    return DropTarget(
      enable: enabled,
      onDragEntered: (_) => _setHovering(true),
      onDragExited: (_) => _setHovering(false),
      onDragDone: _onDone,
      child: Stack(
        children: <Widget>[
          widget.child,
          if (_hovering && enabled)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: colors.bg.withValues(alpha: 0.8),
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border.all(color: colors.accent),
                        borderRadius: BorderRadius.circular(AppRadius.large),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.file_download_outlined, color: colors.accent),
                            const SizedBox(width: 8),
                            Text(
                              Localization.of(context).dropToAttach,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
