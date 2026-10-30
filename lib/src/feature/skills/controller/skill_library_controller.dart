import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'skill_library_controller.freezed.dart';

/// What the Skills and rules screen shows for one project.
@freezed
sealed class SkillLibraryState with _$SkillLibraryState {
  /// Nothing is watched yet.
  const factory SkillLibraryState.idle() = SkillLibrary$IdleState;

  /// The first library of [projectId] has not arrived yet.
  const factory SkillLibraryState.loading({int? projectId}) = SkillLibrary$LoadingState;

  /// The current [library] of [projectId].
  const factory SkillLibraryState.loaded({required SkillLibrary library, int? projectId}) =
      SkillLibrary$LoadedState;

  /// The library of [projectId] could not be read; the previous one stays in
  /// [SkillLibraryController.library] and the next change loads again.
  const factory SkillLibraryState.failed({required Object error, int? projectId}) =
      SkillLibrary$FailedState;
}

/// Follows the skills and rules of one project at a time (the one open in the window).
final class SkillLibraryController extends StateController<SkillLibraryState>
    with SequentialControllerHandler {
  SkillLibraryController({
    required this._repository,
    super.initialState = const SkillLibraryState.idle(),
  });

  final ISkillsRepository _repository;
  StreamSubscription<SkillLibrary>? _subscription;
  bool _watching = false;
  int? _projectId;
  String? _projectRoot;
  SkillLibrary _library = SkillLibrary.empty;

  /// The last library that was loaded for the watched project; empty before the first one.
  SkillLibrary get library => _library;

  /// Follows the library of [projectId], whose folder is [projectRoot]: cancels the previous
  /// subscription and starts a new one. Calling it again with the same arguments changes nothing.
  void watch({int? projectId, String? projectRoot}) => handle(() async {
    if (_watching && _projectId == projectId && _projectRoot == projectRoot) return;
    _watching = true;
    _projectId = projectId;
    _projectRoot = projectRoot;
    // The enablement belongs to the project, so the previous one's library must not linger.
    _library = SkillLibrary.empty;
    setState(SkillLibraryState.loading(projectId: projectId));
    await _subscription?.cancel();
    _subscription = _repository
        .watch(projectId: projectId, projectRoot: projectRoot)
        .listen(
          (library) {
            if (_projectId != projectId || _projectRoot != projectRoot) return;
            setState(SkillLibraryState.loaded(library: _library = library, projectId: projectId));
          },
          onError: (Object error) {
            if (_projectId != projectId || _projectRoot != projectRoot) return;
            setState(SkillLibraryState.failed(error: error, projectId: projectId));
          },
        );
  }, error: (error, stackTrace) async => setState(SkillLibraryState.failed(error: error)));

  @override
  void dispose() {
    _subscription?.cancel().ignore();
    super.dispose();
  }
}
