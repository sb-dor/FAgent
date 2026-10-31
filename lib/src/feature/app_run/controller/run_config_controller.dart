import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/run_config_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'run_config_controller.freezed.dart';

@freezed
sealed class RunConfigState with _$RunConfigState {
  /// Nothing has been saved yet.
  const factory RunConfigState.initial() = RunConfig$InitialState;

  /// A save is running.
  const factory RunConfigState.inProgress() = RunConfig$InProgressState;

  /// The last save failed with [error].
  const factory RunConfigState.error({Object? error}) = RunConfig$ErrorState;

  /// The last save finished.
  const factory RunConfigState.completed() = RunConfig$CompletedState;
}

/// Saves the run arguments of a project (the "Run arguments" dialog).
///
/// One save at a time: a tap during another one is dropped. The new arguments reach the Run tab
/// through `RunController`, which follows the repository.
final class RunConfigController extends StateController<RunConfigState>
    with DroppableControllerHandler {
  RunConfigController({
    required this._repository,
    super.initialState = const RunConfigState.initial(),
  });

  final IRunConfigRepository _repository;

  /// Stores [arguments] as the arguments of [projectId].
  void save(int projectId, RunArguments arguments) => handle(() async {
    setState(const RunConfigState.inProgress());
    await _repository.save(projectId, arguments);
    setState(const RunConfigState.completed());
  }, error: (error, stackTrace) async => setState(RunConfigState.error(error: error)));
}
