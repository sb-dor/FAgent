import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/constant/window_constants.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/app_settings/controller/app_settings_controller.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/chat_search/widgets/chat_search_dialog.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/project_opening/controller/project_opening_controller.dart';
import 'package:flutter_code_agent/src/feature/project_opening/data/project_opening_repository.dart';
import 'package:flutter_code_agent/src/feature/projects/controller/project_removal_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/controller/projects_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/data/projects_repository.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/session_creation/controller/session_creation_controller.dart';
import 'package:flutter_code_agent/src/feature/session_creation/data/session_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/sessions/controller/sessions_controller.dart';
import 'package:flutter_code_agent/src/feature/sessions/data/sessions_repository.dart';
import 'package:flutter_code_agent/src/feature/sessions/models/chat_session.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_sidebar_order.dart';
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
/// project becomes selected, a created chat becomes selected.
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
  late final ProjectRemovalController projectRemovalController;
  late final SessionsController sessionsController;
  late final SessionCreationController sessionCreationController;
  final WorkspaceDataController dataController = WorkspaceDataController();

  /// The window-level settings (panels, theme, language).
  late final AppSettingsController settingsController = AppSettingsConfigInhWidget.of(context)
      .controller;

  @override
  void initState() {
    super.initState();
    final dependencies = Dependencies.of(context);
    final projectsRepository = ProjectsRepositoryImpl(
      database: dependencies.database,
      hub: dependencies.agentHub,
    );
    projectsController = ProjectsController(repository: projectsRepository)..watch();
    projectRemovalController = ProjectRemovalController(repository: projectsRepository)
      ..addListener(_onProjectRemoved);
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
    sessionsController.watchAll();
  }

  @override
  void dispose() {
    dataController.dispose();
    projectOpeningController
      ..removeListener(_onProjectOpened)
      ..dispose();
    sessionCreationController
      ..removeListener(_onSessionCreated)
      ..dispose();
    projectRemovalController
      ..removeListener(_onProjectRemoved)
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

  /// Shows or hides the sidebar and remembers the choice.
  void toggleSidebar() => settingsController.update(
    (current) => current.copyWith(sidebarVisible: !current.sidebarVisible),
  );

  /// Shows or hides the right pane and remembers the choice.
  ///
  /// While the user has not chosen, the pane is open in a wide window ([kWideWindowWidth]), so the
  /// first toggle closes it there and opens it in a narrow one.
  void toggleRightPane({required double windowWidth}) => settingsController.update(
    (current) => current.copyWith(
      rightPaneVisible: !(current.rightPaneVisible ?? windowWidth >= kWideWindowWidth),
    ),
  );

  /// Remembers the right pane width, kept within the allowed range.
  void setRightPaneWidth(double width) => settingsController.update(
    (current) => current.copyWith(
      rightPaneWidth: width.clamp(AppSettings.minRightPaneWidth, AppSettings.maxRightPaneWidth),
    ),
  );

  /// Shows the edit of [path]: opens the right pane if it is hidden, switches it to the Changes
  /// tab and selects the file there.
  void openChange(String path) {
    final wide = MediaQuery.sizeOf(context).width >= kWideWindowWidth;
    if (!(settingsController.settings.rightPaneVisible ?? wide)) {
      settingsController.update((current) => current.copyWith(rightPaneVisible: true));
    }
    dataController
      ..selectPaneTab(RightPaneTab.changes)
      ..selectChange(path);
  }

  /// The project a new chat goes to by default: the one of the selected chat, else the selected
  /// project, else the first group of the sidebar, else none.
  int? get newChatProjectId {
    final chats = switch (sessionsController.state) {
      Sessions$CompletedState(:final sessions) => sessions,
      _ => const <ChatSession>[],
    };
    final sessionId = dataController.sessionId;
    if (sessionId != null) {
      final chat = chats.where((chat) => chat.id == sessionId).firstOrNull;
      if (chat != null) return chat.projectId;
    }
    final selected = dataController.projectId;
    if (selected != null) return selected;
    final projects = switch (projectsController.state) {
      Projects$CompletedState(:final projects) => projects,
      _ => const <Project>[],
    };
    return orderProjectsForSidebar(projects, chats).firstOrNull?.id;
  }

  /// Starts a new chat in [projectId], by default in [newChatProjectId]; does nothing without a
  /// project. The project becomes selected and the window leaves Skills or Settings for the chat;
  /// the new chat is selected when it is created.
  void createChat({int? projectId}) {
    final project = projectId ?? newChatProjectId;
    if (project == null) return;
    dataController.selectProject(project);
    if (dataController.view != WorkspaceView.chat) dataController.backToChat();
    sessionCreationController.create(
      projectId: project,
      agentId: settingsController.settings.defaultAgentId,
    );
  }

  /// Asks which chat to open, then opens it: its project and the chat become selected and the
  /// window leaves Skills or Settings for the chat.
  Future<void> openChatSearch() async {
    final result = await showChatSearch(context);
    if (result == null || !mounted) return;
    dataController
      ..selectProject(result.projectId)
      ..selectSession(result.sessionId);
    if (dataController.view != WorkspaceView.chat) dataController.backToChat();
  }

  /// Shows [project]'s folder in Finder.
  Future<void> revealProject(Project project) async {
    try {
      await projectsController.reveal(project.path);
    } on Object {
      _showError();
    }
  }

  /// Asks, then forgets [project] with its chats; the folder on disk stays.
  Future<void> removeProject(Project project) async {
    final localization = Localization.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
        content: Text(localization.removeProjectConfirm(project.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localization.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.colors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(localization.remove),
          ),
        ],
      ),
    );
    if (confirmed == true) projectRemovalController.remove(project.id);
  }

  void _onProjectRemoved() {
    switch (projectRemovalController.state) {
      case ProjectRemoval$CompletedState(:final projectId):
        if (dataController.projectId == projectId) dataController.clearSelection();
      case ProjectRemoval$BusyState():
        _showMessage(Localization.of(context).removeProjectBusy);
      case ProjectRemoval$ErrorState():
        _showError();
      default:
        break;
    }
  }

  void _showError() => _showMessage(Localization.of(context).somethingWentWrong);

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
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

  @override
  Widget build(BuildContext context) =>
      WorkspaceConfigInhWidget(state: this, child: const WorkspaceWidget());
}
