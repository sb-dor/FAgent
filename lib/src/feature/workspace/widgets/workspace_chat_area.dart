import 'package:control/control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/projects/controller/projects_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/skill_library_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/models/chat_skills.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// {@template workspace_chat_area}
/// The selected chat, or a hint to pick one.
/// {@endtemplate}
class WorkspaceChatArea extends StatefulWidget {
  /// {@macro workspace_chat_area}
  const WorkspaceChatArea({super.key});

  @override
  State<WorkspaceChatArea> createState() => _WorkspaceChatAreaState();
}

class _WorkspaceChatAreaState extends State<WorkspaceChatArea> {
  late final _scope = WorkspaceConfigInhWidget.of(context);

  /// The skills of [project] once its library is loaded; nothing while another project's library
  /// or none is, so the chip does not show the wrong count. A library that failed to load after it
  /// had loaded keeps the last one.
  ChatSkills _chatSkills(Project project) {
    final controller = _scope.skillLibraryController;
    final loaded = switch (controller.state) {
      SkillLibrary$LoadedState(:final projectId) => projectId == project.id,
      SkillLibrary$FailedState(:final projectId) =>
        projectId == project.id && controller.library.skills.isNotEmpty,
      _ => false,
    };
    return loaded ? ChatSkills.of(controller.library, projectName: project.name) : ChatSkills.empty;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Expanded(
        child: StateConsumer<ProjectsController, ProjectsState>(
          controller: _scope.projectsController,
          builder: (context, _, _) => ListenableBuilder(
            listenable: _scope.dataController,
            builder: (context, _) {
              final project = _scope.selectedProject;
              final sessionId = _scope.dataController.sessionId;
              if (project == null || sessionId == null) {
                // Without any project the way forward is to open one; with projects, to pick or
                // start a chat.
                final hasProjects = switch (_scope.projectsController.state) {
                  Projects$CompletedState(:final projects) => projects.isNotEmpty,
                  _ => false,
                };
                return _Hint(
                  text: hasProjects
                      ? Localization.of(context).selectChat
                      : Localization.of(context).chatPlaceholder,
                );
              }
              return ListenableBuilder(
                listenable: Listenable.merge(<Listenable>[
                  _scope.runController,
                  _scope.skillLibraryController,
                ]),
                builder: (context, _) => ChatConfigWidget(
                  key: ValueKey<int>(sessionId),
                  sessionId: sessionId,
                  project: project,
                  onHandle: _scope.dataController.publishChatHandle,
                  onOpenChange: _scope.openChange,
                  runContext: _scope.runLink.mentions,
                  chatSkills: _chatSkills(project),
                  onOpenSkills: _scope.dataController.openSkills,
                ),
              );
            },
          ),
        ),
      ),
    ],
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(text, style: theme.textTheme.bodyLarge?.copyWith(color: context.colors.muted)),
    );
  }
}
