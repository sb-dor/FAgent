import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/project_opening/controller/project_opening_controller.dart';
import 'package:flutter_code_agent/src/feature/project_opening/data/project_opening_repository.dart';
import 'package:flutter_code_agent/src/feature/projects/controller/projects_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/data/projects_repository.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/session_creation/controller/session_creation_controller.dart';
import 'package:flutter_code_agent/src/feature/session_creation/data/session_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/sessions/controller/sessions_controller.dart';
import 'package:flutter_code_agent/src/feature/sessions/data/sessions_repository.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';

/// Gives the workspace widgets access to [WorkspaceConfigWidgetState].
class WorkspaceConfigInhWidget extends InheritedWidget {
  const WorkspaceConfigInhWidget({super.key, required this.state, required super.child});

  final WorkspaceConfigWidgetState state;

  static WorkspaceConfigWidgetState of(BuildContext context) {
    final widget = context
        .getElementForInheritedWidgetOfExactType<WorkspaceConfigInhWidget>()
        ?.widget;
    assert(widget != null, 'WorkspaceConfigInhWidget was not found in element tree');
    return (widget! as WorkspaceConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(WorkspaceConfigInhWidget oldWidget) => false;
}

/// {@template workspace_config_widget}
/// Owns the sidebar controllers and the selection, and wires them: an opened
/// project becomes selected, a created chat becomes selected, a selected
/// project shows its chats.
/// {@endtemplate}
class WorkspaceConfigWidget extends StatefulWidget {
  /// {@macro workspace_config_widget}
  const WorkspaceConfigWidget({super.key});

  @override
  State<WorkspaceConfigWidget> createState() => WorkspaceConfigWidgetState();
}

class WorkspaceConfigWidgetState extends State<WorkspaceConfigWidget> {
  late final ProjectsController projectsController;
  late final ProjectOpeningController projectOpeningController;
  late final SessionsController sessionsController;
  late final SessionCreationController sessionCreationController;
  final WorkspaceDataController dataController = WorkspaceDataController();

  @override
  void initState() {
    super.initState();
    final dependencies = Dependencies.of(context);
    projectsController = ProjectsController(
      repository: ProjectsRepositoryImpl(database: dependencies.database),
    )..watch();
    projectOpeningController = ProjectOpeningController(
      repository: ProjectOpeningRepositoryImpl(database: dependencies.database),
    )..addListener(_onProjectOpened);
    sessionsController = SessionsController(
      repository: SessionsRepositoryImpl(
        database: dependencies.database,
        hub: dependencies.agentHub,
      ),
    );
    sessionCreationController = SessionCreationController(
      repository: SessionCreationRepositoryImpl(database: dependencies.database),
    )..addListener(_onSessionCreated);
    dataController.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    dataController
      ..removeListener(_onSelectionChanged)
      ..dispose();
    projectOpeningController
      ..removeListener(_onProjectOpened)
      ..dispose();
    sessionCreationController
      ..removeListener(_onSessionCreated)
      ..dispose();
    projectsController.dispose();
    sessionsController.dispose();
    super.dispose();
  }

  /// The selected project with its latest data (trust changes, renames).
  Project? get selectedProject {
    final id = dataController.projectId;
    if (id == null) return null;
    return switch (projectsController.state) {
      Projects$CompletedState(:final projects) => projects.where((p) => p.id == id).firstOrNull,
      _ => null,
    };
  }

  /// Picks a folder and opens it as a project.
  Future<void> pickAndOpenProject() async {
    final path = await getDirectoryPath(confirmButtonText: Localization.of(context).openProject);
    if (path != null) projectOpeningController.open(path);
  }

  /// Starts a new chat in the selected project.
  void createChat() {
    final project = dataController.projectId;
    if (project != null) sessionCreationController.create(projectId: project, agentId: 'claude');
  }

  void _onProjectOpened() {
    switch (projectOpeningController.state) {
      case ProjectOpening$CompletedState(:final project):
        dataController.selectProject(project.id);
      case ProjectOpening$ErrorState(:final error):
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(Localization.of(context).openProjectFailed('$error'))),
        );
      default:
        break;
    }
  }

  void _onSessionCreated() {
    if (sessionCreationController.state case SessionCreation$CompletedState(:final sessionId)) {
      dataController.selectSession(sessionId);
    }
  }

  int? _watchedProject;

  void _onSelectionChanged() {
    final project = dataController.projectId;
    if (project != null && project != _watchedProject) {
      _watchedProject = project;
      sessionsController.watch(project);
    }
  }

  @override
  Widget build(BuildContext context) =>
      WorkspaceConfigInhWidget(state: this, child: const WorkspaceWidget());
}
