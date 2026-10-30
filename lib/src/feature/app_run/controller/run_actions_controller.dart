import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'run_actions_controller.freezed.dart';

@freezed
sealed class RunActionsState with _$RunActionsState {
  const factory RunActionsState.initial() = RunActions$InitialState;

  const factory RunActionsState.inProgress() = RunActions$InProgressState;

  const factory RunActionsState.error({Object? error}) = RunActions$ErrorState;

  /// The last action finished; [picked] is the widget `pickWidget` returned, `null` for the others
  /// or when nothing was picked.
  const factory RunActionsState.completed({PickedWidget? picked}) = RunActions$CompletedState;
}

/// The buttons of the Run tab: start, stop, hot reload, hot restart and the widget picker.
///
/// One action at a time: a tap during another one is dropped. The run itself is observed through
/// `RunController`.
final class RunActionsController extends StateController<RunActionsState>
    with DroppableControllerHandler {
  RunActionsController({
    required this._runRepository,
    required this._pickerRepository,
    super.initialState = const RunActionsState.initial(),
  });

  final IAppRunRepository _runRepository;
  final IWidgetPickerRepository _pickerRepository;

  /// Starts the app of [projectId] with the selection the Run tab shows.
  void start(
    int projectId, {
    required String deviceId,
    required BuildMode mode,
    required String target,
  }) => _run(() => _runRepository.start(projectId, deviceId: deviceId, mode: mode, target: target));

  /// Stops the app.
  void stop(int projectId) => _run(() => _runRepository.stop(projectId));

  /// Hot-reloads the app.
  void hotReload(int projectId) => _run(() => _runRepository.hotReload(projectId));

  /// Hot-restarts the app.
  void hotRestart(int projectId) => _run(() => _runRepository.hotRestart(projectId));

  /// Lets the user pick a widget in the app; completes with it, or with `null` if none was picked.
  void pickWidget(int projectId) => handle(() async {
    setState(const RunActionsState.inProgress());
    final picked = await _pickerRepository.pick(projectId);
    setState(RunActionsState.completed(picked: picked));
  }, error: (error, stackTrace) async => setState(RunActionsState.error(error: error)));

  void _run(Future<Object?> Function() action) => handle(() async {
    setState(const RunActionsState.inProgress());
    await action();
    setState(const RunActionsState.completed());
  }, error: (error, stackTrace) async => setState(RunActionsState.error(error: error)));
}
