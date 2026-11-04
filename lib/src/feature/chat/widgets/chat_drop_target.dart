import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/drop_zone/drop_zone_event.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/drop_zone_overlay.dart';

/// {@template chat_drop_target}
/// Takes files dragged onto the whole chat: while they hover the chat shows a [DropZoneOverlay],
/// and the dropped paths go to [onDropped] in drop order.
///
/// [events] are the drags over the whole window (the app's `DropZone`); the chat takes those whose
/// position falls inside its own rectangle. A drop of which some items could not be received (a
/// file promise that failed) says so in one line.
///
/// A chat that is hidden (another page of the workspace is shown) or under a dialog takes no
/// drop: the window reports a drag to every target, seen or not.
/// {@endtemplate}
class ChatDropTarget extends StatefulWidget {
  /// {@macro chat_drop_target}
  const ChatDropTarget({
    required this.events,
    required this.onDropped,
    required this.child,
    super.key,
  });

  /// The drags over the window.
  final Stream<DropZoneEvent> events;

  /// Called with the absolute paths of the dropped files and folders.
  final ValueChanged<List<String>> onDropped;

  /// The chat.
  final Widget child;

  @override
  State<ChatDropTarget> createState() => _ChatDropTargetState();
}

class _ChatDropTargetState extends State<ChatDropTarget> {
  StreamSubscription<DropZoneEvent>? _subscription;
  bool _hovering = false;

  /// Shown and on top; set in [build], which depends on both.
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.events.listen(_onEvent);
  }

  @override
  void didUpdateWidget(ChatDropTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.events != widget.events) {
      _subscription?.cancel();
      _subscription = widget.events.listen(_onEvent);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _setHovering(bool hovering) {
    if (_hovering != hovering && mounted) setState(() => _hovering = hovering);
  }

  /// [event] falls inside this chat as it is laid out now.
  bool _contains(DropZoneEvent event) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return false;
    final local = box.globalToLocal(Offset(event.dx, event.dy));
    return box.paintBounds.contains(local);
  }

  void _onEvent(DropZoneEvent event) {
    if (!mounted) return;
    final inside = _enabled && _contains(event);
    switch (event) {
      case DropZoneEvent$Enter() || DropZoneEvent$Over():
        _setHovering(inside);
      case DropZoneEvent$Leave():
        _setHovering(false);
      case DropZoneEvent$Drop(:final paths, :final failed):
        _setHovering(false);
        if (!inside) return;
        if (paths.isNotEmpty) widget.onDropped(paths);
        if (failed > 0) {
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(SnackBar(content: Text(Localization.of(context).dropFailed)));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The workspace hides the chat with Offstage and a disabled TickerMode.
    _enabled = TickerMode.valuesOf(context).enabled && (ModalRoute.isCurrentOf(context) ?? true);
    return Stack(
      children: <Widget>[
        widget.child,
        if (_hovering && _enabled) const Positioned.fill(child: DropZoneOverlay()),
      ],
    );
  }
}
