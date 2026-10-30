import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/projects/controller/projects_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/skill_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/skill_library_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/skill_text_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_exceptions.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/controllers/skills_view_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skill_error_message.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skill_name_dialog.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// Gives the widgets of the Skills screen access to [SkillsConfigWidgetState].
class SkillsConfigInhWidget extends InheritedWidget {
  const SkillsConfigInhWidget({super.key, required this.state, required super.child});

  final SkillsConfigWidgetState state;

  static SkillsConfigWidgetState of(BuildContext context) {
    final widget = context.getElementForInheritedWidgetOfExactType<SkillsConfigInhWidget>()?.widget;
    assert(widget != null, 'SkillsConfigInhWidget was not found in element tree');
    return (widget! as SkillsConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(SkillsConfigInhWidget oldWidget) => false;
}

/// {@template skills_config_widget}
/// Owns the controllers of the Skills screen: the library of the screen's project, the actions on
/// it, the text of the open item and what the screen shows ([SkillsViewController]).
///
/// The screen starts on the project selected in the window, or on the one the window asked for
/// with `WorkspaceDataController.openSkills`.
///
/// It also owns what the buttons of the screen do (create, import, generate, try in chat), what
/// happens to unsaved edits when the open item changes, and what the user is told when an action
/// fails.
/// {@endtemplate}
class SkillsConfigWidget extends StatefulWidget {
  /// {@macro skills_config_widget}
  const SkillsConfigWidget({required this.child, super.key});

  /// The screen.
  final Widget child;

  @override
  State<SkillsConfigWidget> createState() => SkillsConfigWidgetState();
}

class SkillsConfigWidgetState extends State<SkillsConfigWidget> {
  late final SkillLibraryController library;
  late final SkillActionsController actions;
  late final SkillTextController text;
  late final SkillsViewController view;
  late final WorkspaceConfigWidgetState _workspace;

  /// Whether the editor holds text that is not saved. The editor of the open item keeps it up to
  /// date.
  bool hasUnsavedEdits = false;

  /// Changes when the unsaved edits were dropped on purpose while the item stays open (the user
  /// agreed to lose them); the card then starts a fresh editor.
  final ValueNotifier<int> editorResets = ValueNotifier<int>(0);

  /// Asks the user for a folder; the argument is the text of the confirm button. Tests replace it,
  /// because the native picker cannot be driven from a widget test.
  @visibleForTesting
  Future<String?> Function(String confirmButtonText) pickFolder = (confirmButtonText) =>
      getDirectoryPath(confirmButtonText: confirmButtonText);

  /// Whether the name dialog is open: it explains the name errors itself.
  bool _naming = false;

  /// Whether the user already agreed to lose the unsaved edits for an action that ends by opening
  /// a new item (create, import, duplicate), so the item opens without asking again.
  bool _discardAgreed = false;

  /// The project of the screen with its latest data; `null` when the screen has none.
  Project? get project => _projectById(view.projectId);

  /// Notifies when the projects change.
  Listenable get projectsListenable => _workspace.projectsController;

  /// The projects the screen can switch between.
  List<Project> get projects => _projects ?? const <Project>[];

  List<Project>? get _projects => switch (_workspace.projectsController.state) {
    Projects$CompletedState(:final projects) => projects,
    _ => null,
  };

  Project? _projectById(int? id) {
    if (id == null) return null;
    return _projects?.where((project) => project.id == id).firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    _workspace = WorkspaceConfigInhWidget.of(context);
    final repository = Dependencies.of(context).skillsRepository;
    library = SkillLibraryController(repository: repository);
    actions = SkillActionsController(repository: repository);
    text = SkillTextController(repository: repository);
    final data = _workspace.dataController;
    view = SkillsViewController(
      kind: data.section == 'rules' ? KnowledgeKind.rule : KnowledgeKind.skill,
      projectId: data.projectId,
    );
    data
      ..addListener(_takeTarget)
      ..leaveGuard = confirmDiscard;
    actions.addListener(_onAction);
    _workspace.projectsController.addListener(_syncLibrary);
    view.addListener(_syncLibrary);
    _takeTarget();
    _syncLibrary();
  }

  @override
  void dispose() {
    _workspace.dataController.removeListener(_takeTarget);
    if (_workspace.dataController.leaveGuard == confirmDiscard) {
      _workspace.dataController.leaveGuard = null;
    }
    actions.removeListener(_onAction);
    _workspace.projectsController.removeListener(_syncLibrary);
    view
      ..removeListener(_syncLibrary)
      ..dispose();
    text.dispose();
    actions.dispose();
    library.dispose();
    editorResets.dispose();
    super.dispose();
  }

  /// Applies the window's request to open an item (and a project), if there is one.
  void _takeTarget() {
    final target = _workspace.dataController.takeSkillsTarget();
    if (target == null) return;
    if (target.projectId != null) view.setProject(target.projectId);
    if (target.itemId != null) view.reveal(target.itemId!);
  }

  /// Watches the library of the project of the screen. A project that is gone (removed) is dropped
  /// from the screen once the project list is known; until then nothing is watched, so the library
  /// is not loaded twice.
  void _syncLibrary() {
    switch (_workspace.projectsController.state) {
      case Projects$InitialState() || Projects$InProgressState():
        return;
      case Projects$CompletedState():
        if (view.projectId != null && project == null) {
          view.setProject(null);
          return;
        }
      case Projects$ErrorState():
        break;
    }
    final current = project;
    library.watch(projectId: current?.id, projectRoot: current?.path);
  }

  /// Tells the user about a failed action, and opens the item a finished one made.
  void _onAction() {
    switch (actions.state) {
      case SkillActions$FailedState(:final error):
        // The name dialog explains these two under its field; the editor asks about a conflict.
        final nameError =
            error is InvalidKnowledgeNameException || error is KnowledgeExistsException;
        if (!(_naming && nameError) && error is! KnowledgeConflictException) {
          _discardAgreed = false;
          showMessage(skillErrorMessage(Localization.of(context), error));
        }
      case SkillActions$CompletedState(:final id?):
        open(id);
        _discardAgreed = false;
      case SkillActions$IdleState() ||
          SkillActions$ProcessingState() ||
          SkillActions$CompletedState():
        break;
    }
  }

  /// Shows [message] in a snack bar.
  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Says that the thing the user tapped arrives with milestone M3.
  void showComingSoon() => showMessage(Localization.of(context).comingInMilestone('M3'));

  /// Whether the open item may be dropped: yes when nothing is unsaved, else after the user agrees
  /// to lose the edits. The edits stay (and so does [hasUnsavedEdits]) until the item is dropped.
  Future<bool> confirmDiscard() async {
    if (!hasUnsavedEdits) return true;
    final localization = Localization.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
        title: Text(localization.discardChangesTitle),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localization.stay),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.colors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(localization.discardChanges),
          ),
        ],
      ),
    );
    return discard == true && mounted;
  }

  /// Runs [change], which drops the open item, once the user agrees to lose unsaved edits.
  Future<void> guard(VoidCallback change) async {
    if (!hasUnsavedEdits || _discardAgreed) return change();
    if (await confirmDiscard()) change();
  }

  /// Opens the item [id] in the list.
  Future<void> select(String id) async {
    if (id != view.selectedId) await guard(() => view.select(id));
  }

  /// Opens the item [id] whatever the filter and the search say.
  Future<void> open(String id) => guard(() => view.reveal(id));

  /// Opens a section.
  Future<void> chooseKind(KnowledgeKind kind) async {
    if (kind == view.kind) return view.setKind(kind);
    await guard(() => view.setKind(kind));
  }

  /// Makes [projectId] the project of the screen; the open item of the old project is dropped.
  ///
  /// Unsaved edits are asked about whenever the project really changes: the library of the new
  /// project is loaded from scratch. After a yes the edits are dropped, even when the open item
  /// (a Mine or built-in one) stays open.
  Future<void> chooseProject(int? projectId) async {
    if (projectId == view.projectId) return;
    final edited = hasUnsavedEdits;
    await guard(() {
      view.setProject(projectId);
      if (edited) editorResets.value++;
    });
  }

  /// Asks about the unsaved edits before an action that ends by opening a new item. After a yes
  /// the item opens without another question, until the action is over ([_discardAgreed]).
  Future<bool> _agreeToLeave() async {
    if (!await confirmDiscard()) return false;
    _discardAgreed = hasUnsavedEdits;
    return true;
  }

  /// Asks for a name and creates a skill or rule in the open section.
  ///
  /// Unsaved edits are settled before the dialog opens, so no other dialog can appear on top of it.
  Future<void> createItem() async {
    if (!await _agreeToLeave() || !mounted) return;
    _naming = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => SkillNameDialog(scope: this, kind: view.kind),
      );
    } finally {
      _naming = false;
      _discardAgreed = false;
    }
  }

  /// Asks for a folder and copies it among the user's skills.
  Future<void> importFromFolder() async {
    if (!await _agreeToLeave() || !mounted) return;
    final path = await pickFolder(Localization.of(context).skillsPickFolder);
    if (path != null && mounted) {
      actions.importFolder(path);
    } else {
      _discardAgreed = false;
    }
  }

  /// Starts a chat in the screen's project with the request to write a skill. Does nothing
  /// without a project.
  void generateWithAgent() {
    final projectId = view.projectId;
    if (projectId == null) return;
    // Leaving the screen asks about unsaved edits by itself.
    _workspace.createChat(
      projectId: projectId,
      draft: Localization.of(context).skillGeneratePrompt,
    );
  }

  /// Copies the read-only [item] among the user's items; the copy opens when it is ready.
  Future<void> duplicate(KnowledgeItem item) async {
    if (!await _agreeToLeave()) return;
    actions.duplicate(item.id, projectRoot: project?.path);
  }

  /// Goes back to the chat and starts the composer with `/<name> `; says so when there is no chat.
  void tryInChat(KnowledgeItem item) {
    final handle = _workspace.dataController.chatHandle.value;
    if (handle == null) return showMessage(Localization.of(context).noChatForSkill);
    final data = _workspace.dataController;
    data.whenMayLeave(() {
      data.backToChat();
      // The chat takes focus once it is shown again, so the draft goes in after the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => handle.insertDraft('/${item.name} '));
    });
  }

  @override
  Widget build(BuildContext context) => SkillsConfigInhWidget(state: this, child: widget.child);
}
