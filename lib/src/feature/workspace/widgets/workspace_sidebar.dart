import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_code_agent/src/feature/projects/controller/projects_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/sessions/controller/sessions_controller.dart';
import 'package:flutter_code_agent/src/feature/sessions/models/chat_session.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_chat_tile.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_project_group.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_sidebar_footer.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_sidebar_order.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_sidebar_row.dart';

enum _ProjectAction { reveal, settings, remove }

enum _AddProjectAction { openFolder, newFlutter, clone }

/// One line of the scrolling list: a project title, one of its chats, or a hint.
sealed class _ListItem {
  const _ListItem();
}

final class _HeaderItem extends _ListItem {
  const _HeaderItem(this.project, {required this.collapsed});

  final Project project;
  final bool collapsed;
}

final class _ChatItem extends _ListItem {
  const _ChatItem(this.session);

  final ChatSession session;
}

final class _HintItem extends _ListItem {
  const _HintItem();
}

/// {@template workspace_sidebar}
/// New chat and search on top, then the chats of every project grouped by project, then the
/// add-project button and the footer.
///
/// Projects are ordered by their most recent chat; projects without chats follow in the order of
/// the project list. A group can be collapsed; that is remembered only while the window lives
/// (in [WorkspaceDataController], so hiding the sidebar does not forget it).
/// {@endtemplate}
class WorkspaceSidebar extends StatefulWidget {
  /// {@macro workspace_sidebar}
  const WorkspaceSidebar({super.key});

  @override
  State<WorkspaceSidebar> createState() => _WorkspaceSidebarState();
}

class _WorkspaceSidebarState extends State<WorkspaceSidebar> {
  late final _scope = WorkspaceConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    // Material, not ColoredBox: the rows paint selection and splashes on it.
    return Material(
      color: context.colors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            WorkspaceSidebarRow(
              icon: Icons.edit_outlined,
              label: localization.newChat,
              shortcut: '⌘N',
              outlined: true,
              onTap: _scope.createChat,
            ),
            const SizedBox(height: 4),
            WorkspaceSidebarRow(
              icon: Icons.search,
              label: localization.search,
              shortcut: '⌘K',
              muted: true,
              onTap: _scope.openChatSearch,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge(<Listenable>[
                  _scope.projectsController,
                  _scope.sessionsController,
                  _scope.dataController,
                ]),
                builder: _buildList,
              ),
            ),
            const SizedBox(height: 4),
            Builder(
              builder: (rowContext) => WorkspaceSidebarRow(
                icon: Icons.add,
                label: localization.addProject,
                muted: true,
                trailing: Icon(Icons.expand_more, size: 16, color: context.colors.muted),
                onTap: () => _openAddProjectMenu(_rectOf(rowContext)),
              ),
            ),
            const SizedBox(height: 4),
            Divider(color: context.colors.border),
            const SizedBox(height: 4),
            const WorkspaceSidebarFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, Widget? _) {
    final localization = Localization.of(context);
    final projectsState = _scope.projectsController.state;
    if (projectsState is Projects$ErrorState) return _Message(localization.somethingWentWrong);
    if (projectsState is! Projects$CompletedState) return const SizedBox.shrink();
    if (projectsState.projects.isEmpty) return _Message(localization.noProjectsYet);

    final sessions = switch (_scope.sessionsController.state) {
      Sessions$CompletedState(:final sessions) => sessions,
      _ => const <ChatSession>[],
    };
    final items = _items(projectsState.projects, sessions);
    final selectedSession = _scope.dataController.sessionId;
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => switch (items[index]) {
        _HeaderItem(:final project, :final collapsed) => WorkspaceProjectHeader(
          key: ValueKey<String>('project-${project.id}'),
          project: project,
          collapsed: collapsed,
          onToggle: () => _scope.dataController.toggleCollapsed(project.id),
          onNewChat: () => _scope.createChat(projectId: project.id),
          onMenu: (anchor) => _openProjectMenu(project, anchor),
        ),
        _ChatItem(:final session) => WorkspaceChatTile(
          key: ValueKey<String>('chat-${session.id}'),
          session: session,
          selected: session.id == selectedSession,
          status: _scope.sessionsController.statusOf(session.id),
          onTap: () => _scope.dataController
            ..selectProject(session.projectId)
            ..selectSession(session.id),
        ),
        _HintItem() => const WorkspaceNoChatsHint(),
      },
    );
  }

  List<_ListItem> _items(List<Project> projects, List<ChatSession> sessions) {
    final chatsOf = <int, List<ChatSession>>{};
    for (final session in sessions) {
      (chatsOf[session.projectId] ??= <ChatSession>[]).add(session);
    }
    final collapsedProjects = _scope.dataController.collapsedProjects;
    return <_ListItem>[
      for (final project in orderProjectsForSidebar(projects, sessions)) ...<_ListItem>[
        _HeaderItem(project, collapsed: collapsedProjects.contains(project.id)),
        if (!collapsedProjects.contains(project.id))
          if (chatsOf[project.id] case final chats?)
            for (final chat in chats) _ChatItem(chat)
          else
            const _HintItem(),
      ],
    ];
  }

  Rect _rectOf(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _openProjectMenu(Project project, Rect anchor) async {
    final localization = Localization.of(context);
    final action = await showAppMenu<_ProjectAction>(
      context: context,
      anchor: anchor,
      width: 220,
      sections: <AppMenuSection<_ProjectAction>>[
        AppMenuSection<_ProjectAction>(
          items: <AppMenuItem<_ProjectAction>>[
            AppMenuItem<_ProjectAction>(
              value: _ProjectAction.reveal,
              title: localization.showInFinder,
              icon: Icons.folder_open_outlined,
            ),
            AppMenuItem<_ProjectAction>(
              value: _ProjectAction.settings,
              title: localization.projectSettings,
              icon: Icons.tune,
            ),
            AppMenuItem<_ProjectAction>(
              value: _ProjectAction.remove,
              title: localization.removeProject,
              icon: Icons.delete_outline,
              tone: AppTone.danger,
            ),
          ],
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _ProjectAction.reveal:
        _scope.revealProject(project).ignore();
      case _ProjectAction.settings:
        _scope.dataController.openView(WorkspaceView.skills);
      case _ProjectAction.remove:
        _scope.removeProject(project).ignore();
      case null:
        break;
    }
  }

  Future<void> _openAddProjectMenu(Rect anchor) async {
    final localization = Localization.of(context);
    final action = await showAppMenu<_AddProjectAction>(
      context: context,
      anchor: anchor,
      width: 220,
      sections: <AppMenuSection<_AddProjectAction>>[
        AppMenuSection<_AddProjectAction>(
          items: <AppMenuItem<_AddProjectAction>>[
            AppMenuItem<_AddProjectAction>(
              value: _AddProjectAction.openFolder,
              title: localization.openFolder,
              icon: Icons.folder_open_outlined,
            ),
            AppMenuItem<_AddProjectAction>(
              value: _AddProjectAction.newFlutter,
              title: localization.newFlutterProject,
              icon: Icons.flutter_dash,
            ),
            AppMenuItem<_AddProjectAction>(
              value: _AddProjectAction.clone,
              title: localization.cloneFromGit,
              icon: Icons.cloud_download_outlined,
            ),
          ],
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _AddProjectAction.openFolder:
        _scope.pickAndOpenProject().ignore();
      case _AddProjectAction.newFlutter || _AddProjectAction.clone:
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(localization.comingInMilestone('M4'))));
      case null:
        break;
    }
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall!.copyWith(color: context.colors.muted),
    ),
  );
}
