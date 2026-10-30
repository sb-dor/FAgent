import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/projects/controller/projects_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/skill_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/skill_library_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/skill_text_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/controllers/skills_view_controller.dart';
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
    data.addListener(_takeTarget);
    _workspace.projectsController.addListener(_syncLibrary);
    view.addListener(_syncLibrary);
    _takeTarget();
    _syncLibrary();
  }

  @override
  void dispose() {
    _workspace.dataController.removeListener(_takeTarget);
    _workspace.projectsController.removeListener(_syncLibrary);
    view
      ..removeListener(_syncLibrary)
      ..dispose();
    text.dispose();
    actions.dispose();
    library.dispose();
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

  @override
  Widget build(BuildContext context) => SkillsConfigInhWidget(state: this, child: widget.child);
}
