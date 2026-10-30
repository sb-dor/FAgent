import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
/// does not fit.
/// {@endtemplate}
class WorkspaceChatTile extends StatelessWidget {
  /// {@macro workspace_chat_tile}
  const WorkspaceChatTile({
    required this.session,
    required this.selected,
    required this.status,
    required this.onTap,
    super.key,
  });

  /// The chat.
  final ChatSession session;

  /// Whether the chat is open.
  final bool selected;

  /// Live status of the chat; `null` while it was not opened in this run.
  final ValueListenable<SessionStatus>? status;

  /// Called when the tile is pressed.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = session.title.isEmpty ? Localization.of(context).untitledChat : session.title;
    final status = this.status;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.accentSoft : Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: InkWell(
          onTap: onTap,
          hoverColor: colors.border.withValues(alpha: 0.5),
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
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
