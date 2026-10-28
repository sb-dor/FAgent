import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_chats_list.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_projects_list.dart';

/// {@template workspace_sidebar}
/// Projects on top, the selected project's chats below.
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
    final theme = Theme.of(context);
    final localization = Localization.of(context);
    // Material, not ColoredBox: the list tiles paint selection and splashes on it.
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionHeader(
            title: localization.projects,
            actionTooltip: localization.openProject,
            actionIcon: Icons.create_new_folder_outlined,
            onAction: _scope.pickAndOpenProject,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: const WorkspaceProjectsList(),
          ),
          const Divider(height: 16),
          ListenableBuilder(
            listenable: _scope.dataController,
            builder: (context, _) => _SectionHeader(
              title: localization.chats,
              actionTooltip: localization.newChat,
              actionIcon: Icons.add_comment_outlined,
              onAction: _scope.dataController.projectId == null ? null : _scope.createChat,
            ),
          ),
          const Expanded(child: WorkspaceChatsList()),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionTooltip,
    required this.actionIcon,
    required this.onAction,
  });

  final String title;
  final String actionTooltip;
  final IconData actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
    child: Row(
      children: <Widget>[
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
        IconButton(tooltip: actionTooltip, icon: Icon(actionIcon, size: 20), onPressed: onAction),
      ],
    ),
  );
}
