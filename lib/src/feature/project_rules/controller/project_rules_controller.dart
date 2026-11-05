import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/project_rules/data/project_rules_repository.dart';
import 'package:flutter_code_agent/src/feature/project_rules/models/project_rule.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'project_rules_controller.freezed.dart';

/// Where the offer of the app's rules to a project stands.
@freezed
sealed class ProjectRulesState with _$ProjectRulesState {
  /// Nothing to offer.
  const factory ProjectRulesState.idle() = ProjectRules$IdleState;

  /// Project [projectId] in [root] has no `docs/rules`: [rules] can be added to it.
  const factory ProjectRulesState.offer({
    required int projectId,
    required String root,
    required List<ProjectRule> rules,
  }) = ProjectRules$OfferState;

  /// Project [projectId] has `docs/rules`.
  const factory ProjectRulesState.present({required int projectId}) = ProjectRules$PresentState;

  /// Project [projectId] has no `docs/rules` and was offered them before: it is not asked again,
  /// but the Rules section offers them.
  const factory ProjectRulesState.missing({required int projectId}) = ProjectRules$MissingState;

  /// The chosen rules are being written.
  const factory ProjectRulesState.writing() = ProjectRules$WritingState;

  /// The rules were written into project [projectId].
  const factory ProjectRulesState.written({required int projectId}) = ProjectRules$WrittenState;

  /// Writing failed; the project is offered again later.
  const factory ProjectRulesState.failed({required Object error}) = ProjectRules$FailedState;
}

/// Offers the app's built-in rules to projects without `docs/rules`, and writes the ones the user
/// chose, one project at a time.
final class ProjectRulesController extends StateController<ProjectRulesState>
    with SequentialControllerHandler {
  /// Creates the controller.
  ProjectRulesController({
    required this._repository,
    super.initialState = const ProjectRulesState.idle(),
  });

  final IProjectRulesRepository _repository;

  /// Offers the rules to [project] unless it has `docs/rules` ([ProjectRulesState.present]), was
  /// offered them before or is not a Flutter project ([ProjectRulesState.missing]: the Rules
  /// section still offers them). A project whose folder is gone gets nothing.
  void check(Project project) => handle(() async {
    if (!await _repository.canHaveRules(project.path)) {
      setState(const ProjectRulesState.idle());
    } else if (await _repository.hasRules(project.path)) {
      setState(ProjectRulesState.present(projectId: project.id));
    } else if (project.rulesOffered || !project.isFlutter) {
      setState(ProjectRulesState.missing(projectId: project.id));
    } else {
      await _offer(project);
    }
  });

  /// Offers the rules to [project] (the user asked for it), unless it has `docs/rules`.
  void offer(Project project) => handle(() async {
    if (!await _repository.canHaveRules(project.path)) {
      setState(const ProjectRulesState.idle());
    } else if (await _repository.hasRules(project.path)) {
      setState(ProjectRulesState.present(projectId: project.id));
    } else {
      await _offer(project);
    }
  });

  Future<void> _offer(Project project) async => setState(
    ProjectRulesState.offer(
      projectId: project.id,
      root: project.path,
      rules: await _repository.builtinRules(),
    ),
  );

  /// Writes [chosen] into project [projectId] in [root]; it is not offered again then.
  void add(int projectId, String root, List<ProjectRule> chosen) => handle(() async {
    setState(const ProjectRulesState.writing());
    await _repository.write(root, chosen);
    await _repository.markOffered(projectId);
    setState(ProjectRulesState.written(projectId: projectId));
  }, error: (error, _) async => setState(ProjectRulesState.failed(error: error)));

  /// The user declined for project [projectId]: it is not offered again by itself.
  void dismiss(int projectId) => handle(() async {
    await _repository.markOffered(projectId);
    setState(ProjectRulesState.missing(projectId: projectId));
  });
}
