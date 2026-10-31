import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skills_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'skill_text_controller.freezed.dart';

@freezed
sealed class SkillTextState with _$SkillTextState {
  /// Nothing is loaded.
  const factory SkillTextState.idle() = SkillText$IdleState;

  /// The text of [id] is being read.
  const factory SkillTextState.loading(String id) = SkillText$LoadingState;

  /// The [text] of [id].
  const factory SkillTextState.loaded(String id, String text) = SkillText$LoadedState;

  /// The text of [id] could not be read.
  const factory SkillTextState.failed(String id, Object error) = SkillText$FailedState;
}

/// Loads the text of the skill or rule the editor shows.
///
/// A newer [load] wins: the text of an earlier one never replaces it.
final class SkillTextController extends StateController<SkillTextState>
    with SequentialControllerHandler {
  SkillTextController({
    required this._repository,
    super.initialState = const SkillTextState.idle(),
  });

  final ISkillsRepository _repository;
  int _generation = 0;

  /// Reads the text of [id]; an item of a project needs its [projectRoot].
  void load(String id, {String? projectRoot}) {
    final generation = ++_generation;
    handle(
      () async {
        if (generation != _generation) return;
        setState(SkillTextState.loading(id));
        final text = await _repository.read(id, projectRoot: projectRoot);
        if (generation == _generation) setState(SkillTextState.loaded(id, text));
      },
      error: (error, stackTrace) async {
        if (generation == _generation) setState(SkillTextState.failed(id, error));
      },
    );
  }
}
