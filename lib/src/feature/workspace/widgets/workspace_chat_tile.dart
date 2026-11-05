import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/status.dart';
import 'package:flutter_code_agent/src/feature/sessions/models/chat_session.dart';

/// Tone of the status dot of a chat in [status].
AppStatusTone statusTone(SessionStatus status) => switch (status) {
  SessionStatus.running ||
  SessionStatus.starting ||
  SessionStatus.loading ||
  SessionStatus.creating ||
  SessionStatus.cancelling => AppStatusTone.active,
  SessionStatus.awaitingPermission => AppStatusTone.warn,
  SessionStatus.error ||
  SessionStatus.setupFailed ||
  SessionStatus.needsAuth => AppStatusTone.danger,
  SessionStatus.cold || SessionStatus.idle || SessionStatus.disposed => AppStatusTone.none,
};

/// {@template workspace_chat_tile}
/// A chat in the sidebar: a live status dot and the title, which ends with an ellipsis when it
/// does not fit, and a small label with the agent's name unless the chat is Claude's. A right
/// click, or the ⋯ that shows while the pointer is over the row, opens [onMenu]; while [renaming]
/// the title is a field: Enter renames, Esc or a click elsewhere cancels.
/// {@endtemplate}
class WorkspaceChatTile extends StatefulWidget {
  /// {@macro workspace_chat_tile}
  const WorkspaceChatTile({
    required this.session,
    required this.agentName,
    required this.selected,
    required this.status,
    required this.onTap,
    this.onMenu,
    this.renaming = false,
    this.onRename,
    this.onCancelRename,
    super.key,
  });

  /// The chat.
  final ChatSession session;

  /// Name of the chat's agent, shown beside the title unless the agent is Claude.
  final String agentName;

  /// Whether the chat is open.
  final bool selected;

  /// Live status of the chat; `null` while it was not opened in this run.
  final ValueListenable<SessionStatus>? status;

  /// Called when the tile is pressed.
  final VoidCallback onTap;

  /// Opens the chat's menu at the given rect (global); `null` hides the ⋯.
  final ValueChanged<Rect>? onMenu;

  /// The title is a field to rename the chat.
  final bool renaming;

  /// Called with the new name when Enter is pressed in the field.
  final ValueChanged<String>? onRename;

  /// Called when the rename is given up.
  final VoidCallback? onCancelRename;

  @override
  State<WorkspaceChatTile> createState() => _WorkspaceChatTileState();
}

class _WorkspaceChatTileState extends State<WorkspaceChatTile> {
  /// The ⋯ button's side.
  static const double _menuSize = 22;

  /// Whether the pointer is over the row: only the ⋯ shows then.
  bool _hovered = false;
  TextEditingController? _name;
  final FocusNode _field = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.renaming) _startRename();
  }

  @override
  void didUpdateWidget(WorkspaceChatTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.renaming && !oldWidget.renaming) _startRename();
    if (!widget.renaming && oldWidget.renaming) {
      _name?.dispose();
      _name = null;
    }
  }

  void _startRename() {
    final title = widget.session.title;
    _name = TextEditingController(text: title)
      ..selection = TextSelection(baseOffset: 0, extentOffset: title.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _field.requestFocus();
    });
  }

  @override
  void dispose() {
    _name?.dispose();
    _field.dispose();
    super.dispose();
  }

  void _menuAt(Rect anchor) => widget.onMenu?.call(anchor);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final title = widget.session.title.isEmpty ? localization.untitledChat : widget.session.title;
    final status = widget.status;
    final name = _name;
    return Semantics(
      button: true,
      selected: widget.selected,
      child: MouseRegion(
        cursor: name == null ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        // No ink: a click only changes the row's color, so nothing animates.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: name == null ? widget.onTap : null,
          onSecondaryTapUp: widget.onMenu == null
              ? null
              : (details) => _menuAt(
                  Rect.fromLTWH(details.globalPosition.dx, details.globalPosition.dy, 0, 0),
                ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Only the selection colors the row: hovering changes nothing.
              color: widget.selected ? colors.accentSoft : colors.accentSoft.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: <Widget>[
                  if (status == null)
                    const StatusDot(tone: AppStatusTone.none)
                  else
                    ValueListenableBuilder<SessionStatus>(
                      valueListenable: status,
                      builder: (context, value, _) => StatusDot(tone: statusTone(value)),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: name == null
                        ? Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          )
                        : CallbackShortcuts(
                            bindings: <ShortcutActivator, VoidCallback>{
                              const SingleActivator(LogicalKeyboardKey.escape): () =>
                                  widget.onCancelRename?.call(),
                            },
                            child: TextField(
                              controller: name,
                              focusNode: _field,
                              maxLines: 1,
                              style: Theme.of(context).textTheme.bodyMedium,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              ),
                              onSubmitted: (value) => widget.onRename?.call(value),
                              onTapOutside: (_) => widget.onCancelRename?.call(),
                            ),
                          ),
                  ),
                  if (widget.session.agentId != AgentDefinition.claude.id &&
                      name == null) ...<Widget>[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 72),
                      child: Text(
                        widget.agentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall!
                            .copyWith(color: colors.muted),
                      ),
                    ),
                  ],
                  // The ⋯ has its place even while hidden, so showing it moves nothing.
                  if (name == null && widget.onMenu != null)
                    SizedBox.square(
                      dimension: _menuSize,
                      child: Visibility(
                        visible: _hovered,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: Builder(
                          builder: (buttonContext) => IconButton(
                            tooltip: localization.chatActions,
                            icon: const Icon(Icons.more_horiz),
                            iconSize: 16,
                            color: colors.muted,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: _menuSize,
                              height: _menuSize,
                            ),
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              splashFactory: NoSplash.splashFactory,
                              overlayColor: colors.muted.withValues(alpha: 0),
                            ),
                            onPressed: () {
                              final box = buttonContext.findRenderObject()! as RenderBox;
                              _menuAt(box.localToGlobal(Offset.zero) & box.size);
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
