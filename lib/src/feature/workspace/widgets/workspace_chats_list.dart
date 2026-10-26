import 'package:control/control.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/sessions/controller/sessions_controller.dart';
import 'package:flutter_code_agent/src/feature/sessions/models/chat_session.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// {@template workspace_chats_list}
/// Chats of the selected project with a live status dot each.
/// {@endtemplate}
class WorkspaceChatsList extends StatefulWidget {
  /// {@macro workspace_chats_list}
  const WorkspaceChatsList({super.key});

  @override
  State<WorkspaceChatsList> createState() => _WorkspaceChatsListState();
}

class _WorkspaceChatsListState extends State<WorkspaceChatsList> {
  late final _scope = WorkspaceConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _scope.dataController,
    builder: (context, _) {
      final projectId = _scope.dataController.projectId;
      if (projectId == null) return const SizedBox.shrink();
      return StateConsumer<SessionsController, SessionsState>(
        controller: _scope.sessionsController,
        builder: (context, state, _) => switch (state) {
          Sessions$CompletedState(projectId: final shown, :final sessions)
              when shown == projectId && sessions.isNotEmpty =>
            ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: sessions.length,
              itemBuilder: (context, index) => _ChatTile(
                session: sessions[index],
                selected: sessions[index].id == _scope.dataController.sessionId,
                status: _scope.sessionsController.statusOf(sessions[index].id),
                onTap: () => _scope.dataController.selectSession(sessions[index].id),
              ),
            ),
          Sessions$CompletedState(projectId: final shown) when shown == projectId => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              Localization.of(context).noChatsYet,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _ => const SizedBox.shrink(),
        },
      );
    },
  );
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.session,
    required this.selected,
    required this.status,
    required this.onTap,
  });

  final ChatSession session;
  final bool selected;
  final ValueListenable<SessionStatus>? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = session.title.isEmpty ? Localization.of(context).untitledChat : session.title;
    final dot = status;
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: theme.colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: dot == null
          ? null
          : ValueListenableBuilder<SessionStatus>(
              valueListenable: dot,
              builder: (context, value, _) => _StatusDot(status: value),
            ),
      onTap: onTap,
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (status) {
      SessionStatus.awaitingPermission || SessionStatus.needsAuth => colors.tertiary,
      SessionStatus.error || SessionStatus.setupFailed => colors.error,
      _ when status.isBusy => colors.primary,
      _ => null,
    };
    if (color == null) return const SizedBox.shrink();
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
