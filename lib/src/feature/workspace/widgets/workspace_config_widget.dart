import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/constant/window_constants.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/devices_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
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
import 'package:flutter_code_agent/src/feature/skills/controller/skill_library_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/pending_chat_draft.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_run_link.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_sidebar_order.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:path/path.dart' as p;

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
  late final DevicesController devicesController;
  late final RunController runController;
  late final RunActionsController runActionsController;

  /// The skills of the selected project, for the chats (the 🧩 chip, the `/` menu, the skill lines).
  /// The Skills screen has a library of its own.
  late final SkillLibraryController skillLibraryController;
  final WorkspaceDataController dataController = WorkspaceDataController();

  /// The run of the selected project and its ties to the selected chat.
  late final WorkspaceRunLink runLink;

  /// The text for the chat that is being created (see [createChat]).
  late final PendingChatDraft _draft = PendingChatDraft(data: dataController);

  /// Whether any of the run data (the run, the devices, the widget picker) is made up. Everything
  /// that shows it (the Run tab, the title bar, the `@` menu) says so.
  late final bool runIsPreview;

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
    runIsPreview =
        dependencies.appRunRepository.isPreview ||
        dependencies.devicesRepository.isPreview ||
        dependencies.widgetPickerRepository.isPreview;
    devicesController = DevicesController(repository: dependencies.devicesRepository)..watch();
    runController = RunController(repository: dependencies.appRunRepository);
    runActionsController = RunActionsController(
      runRepository: dependencies.appRunRepository,
      pickerRepository: dependencies.widgetPickerRepository,
    )..addListener(_onRunAction);
    runLink = WorkspaceRunLink(
      data: dataController,
      run: runController,
      actions: runActionsController,
      reloadAfterTurn: () => settingsController.settings.reloadAfterTurn,
      isPreview: runIsPreview,
    );
    skillLibraryController = SkillLibraryController(repository: dependencies.skillsRepository);
    projectsController.addListener(_followSkills);
    devicesController.addListener(_chooseDefaultDevice);
    runController.addListener(_chooseDefaultDevice);
    dataController
      ..addListener(_followSelectedProject)
      ..addListener(_followSkills)
      ..addListener(_draft.onSelectionChanged)
      ..chatHandle.addListener(_draft.onHandleChanged);
    _followSelectedProject();
    _followSkills();
  }

  @override
  void dispose() {
    runLink.dispose();
    projectsController.removeListener(_followSkills);
    dataController
      ..removeListener(_followSelectedProject)
      ..removeListener(_followSkills)
      ..removeListener(_draft.onSelectionChanged)
      ..chatHandle.removeListener(_draft.onHandleChanged)
      ..dispose();
    devicesController.removeListener(_chooseDefaultDevice);
    runController.removeListener(_chooseDefaultDevice);
    runActionsController
      ..removeListener(_onRunAction)
      ..dispose();
    runController.dispose();
    skillLibraryController.dispose();
    devicesController.dispose();
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

  /// The run and its logs follow the selected project.
  void _followSelectedProject() {
    final id = dataController.projectId;
    if (id != null) runController.watch(id);
  }

  /// The skills follow the selected project. They wait for the project list, since the folder of
  /// the project belongs to its skills; without a project (or with one that is gone) nothing new
  /// is followed.
  void _followSkills() {
    final project = selectedProject;
    if (project != null) {
      skillLibraryController.watch(projectId: project.id, projectRoot: project.path);
    }
  }

  /// Picks the first running device for the selected project while none is chosen and the devices
  /// are known, so every way to start the app (the Run tab, the title bar) sees a device whether or
  /// not the Run tab was ever opened. A device the user chose is never replaced.
  void _chooseDefaultDevice() {
    final run = runController.state;
    if (run.projectId == null || run.selectedDeviceId != null) return;
    if (devicesController.state case Devices$CompletedState(:final devices)) {
      final first = devices.where((device) => device.kind == DeviceKind.running).firstOrNull;
      if (first != null) runController.choose(deviceId: first.id);
    }
  }

  /// A picked widget outlives the next action, so it moves to the run state as soon as it arrives.
  /// The pick may finish after the window moved to another project: the widget belongs to the
  /// project it was picked in, so it is dropped unless that project is still the followed one.
  void _onRunAction() {
    if (runActionsController.state case RunActions$CompletedState(:final picked?, :final projectId)
        when projectId == runController.state.projectId) {
      runController.setPicked(picked);
    }
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
  ///
  /// A [draft] is put into the composer of the new chat once it has opened. It is dropped when the
  /// user opens another chat first, or when the chat cannot be created.
  void createChat({int? projectId, String? draft}) {
    final project = projectId ?? newChatProjectId;
    if (project == null) return;
    dataController.selectProject(project);
    if (dataController.view != WorkspaceView.chat) dataController.backToChat();
    // A creation that is already running ignores this one, so it keeps the draft it was given.
    if (sessionCreationController.state is! SessionCreation$InProgressState) _draft.expect(draft);
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

  /// Opens the file at [path] in the default text editor; says so when the file is gone.
  Future<void> openPath(String path) async {
    try {
      await projectsController.openPath(path);
    } on OpenPathRefusedException {
      if (mounted) _showMessage(Localization.of(context).fileMissing);
    } on Object {
      _showError();
    }
  }

  /// Puts the error of the log line [entry] into the open chat's draft (the user sends it), or says
  /// there is no chat.
  void sendRunErrorToAgent(LogEntry entry) {
    if (!runLink.sendError(entry)) _showMessage(Localization.of(context).noChatForError);
  }

  /// Puts the widget picked in the running app into the open chat's draft, or says there is no
  /// chat.
  void addRunWidgetToMessage(PickedWidget picked) {
    if (!runLink.addWidget(picked)) _showMessage(Localization.of(context).noChatForWidget);
  }

  /// Opens [file] of the running app in the editor; a relative path is inside the selected project.
  ///
  /// [line] is not used yet: the file opens in the default text editor (`open -t`), which cannot
  /// jump to a line. The parameter stays for a future editor integration.
  Future<void> openRunFile(String file, int? line) async {
    final root = selectedProject?.path;
    if (p.isAbsolute(file)) return openPath(file);
    if (root != null) return openPath(p.join(root, file));
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
    switch (sessionCreationController.state) {
      case SessionCreation$CompletedState(:final sessionId):
        _draft.created(sessionId);
        dataController.selectSession(sessionId);
      case SessionCreation$ErrorState():
        _draft.forget();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) =>
      WorkspaceConfigInhWidget(state: this, child: const WorkspaceWidget());
}
