import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'skill_actions_controller.freezed.dart';

@freezed
sealed class SkillActionsState with _$SkillActionsState {
  /// No action has been taken.
  const factory SkillActionsState.idle() = SkillActions$IdleState;

  /// An action is running.
  const factory SkillActionsState.processing() = SkillActions$ProcessingState;

  /// The last action finished; [id] is the new item for `create`, `duplicate` and `importFolder`,
  /// `null` for the others.
  const factory SkillActionsState.completed({String? id}) = SkillActions$CompletedState;

  /// The last action failed with [error], for example a `KnowledgeExistsException`.
  const factory SkillActionsState.failed({required Object error}) = SkillActions$FailedState;
}

/// The buttons of the Skills and rules screen: switches, editing, create, duplicate and import.
///
/// One action at a time: a tap during another one is dropped. The result shows up in the library
/// observed through `SkillLibraryController`.
final class SkillActionsController extends StateController<SkillActionsState>
    with DroppableControllerHandler {
  SkillActionsController({
    required this._repository,
    super.initialState = const SkillActionsState.idle(),
  });

  final ISkillsRepository _repository;

  /// Turns [id] on or off for everything ([projectId] is `null`) or as an exception for one
  /// project.
  void setEnabled(String id, {required bool enabled, int? projectId}) =>
      _run(() => _repository.setEnabled(id, enabled: enabled, projectId: projectId));

  /// Makes [projectId] follow the global value of [id] again.
  void clearException(String id, int projectId) =>
      _run(() => _repository.clearException(id, projectId));

  /// Replaces the text of [id]; an item of a project needs its [projectRoot].
  void save(String id, String text, {String? projectRoot}) =>
      _run(() => _repository.write(id, text, projectRoot: projectRoot));

  /// Creates a skill or rule named [name]; completes with its id.
  void create(KnowledgeKind kind, String name) => _run(() => _repository.create(kind, name));

  /// Copies [id] among the user's items; completes with the id of the copy. An item of a project
  /// needs its [projectRoot].
  void duplicate(String id, {String? projectRoot}) =>
      _run(() => _repository.duplicate(id, projectRoot: projectRoot));

  /// Copies the skill folder at [path] among the user's items; completes with its id.
  void importFolder(String path) => _run(() => _repository.importFolder(path));

  void _run(Future<Object?> Function() action) => handle(() async {
    setState(const SkillActionsState.processing());
    final result = await action();
    setState(SkillActionsState.completed(id: result is String ? result : null));
  }, error: (error, stackTrace) async => setState(SkillActionsState.failed(error: error)));
}
