import 'package:control/control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/projects/controller/projects_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// {@template workspace_projects_list}
/// Opened projects; tapping one selects it.
/// {@endtemplate}
class WorkspaceProjectsList extends StatefulWidget {
  /// {@macro workspace_projects_list}
  const WorkspaceProjectsList({super.key});

  @override
  State<WorkspaceProjectsList> createState() => _WorkspaceProjectsListState();
}

class _WorkspaceProjectsListState extends State<WorkspaceProjectsList> {
  late final _scope = WorkspaceConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) => StateConsumer<ProjectsController, ProjectsState>(
    controller: _scope.projectsController,
    builder: (context, state, _) => switch (state) {
      Projects$CompletedState(:final projects) when projects.isNotEmpty => ListenableBuilder(
        listenable: _scope.dataController,
        builder: (context, _) => ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: projects.length,
          itemBuilder: (context, index) => _ProjectTile(
            project: projects[index],
            selected: projects[index].id == _scope.dataController.projectId,
            onTap: () => _scope.dataController.selectProject(projects[index].id),
          ),
        ),
      ),
      Projects$CompletedState() => _Empty(text: Localization.of(context).noProjectsYet),
      Projects$ErrorState() => _Empty(text: Localization.of(context).somethingWentWrong),
      _ => const SizedBox.shrink(),
    },
  );
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project, required this.selected, required this.onTap});

  final Project project;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: theme.colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(project.isFlutter ? Icons.flutter_dash : Icons.folder_outlined, size: 18),
      title: Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(project.path, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
