import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:l/l.dart';

part 'run_actions_controller.freezed.dart';

@freezed
sealed class RunActionsState with _$RunActionsState {
  const factory RunActionsState.initial() = RunActions$InitialState;

  const factory RunActionsState.inProgress() = RunActions$InProgressState;

  const factory RunActionsState.error({Object? error}) = RunActions$ErrorState;

  /// The last action finished for [projectId]; [screenshot] is the path (relative to the project)
  /// of the shot `screenshot` took, `null` for the other actions or when the shot failed. The
  /// window may have moved on to another project by then, so a [screenshot] belongs to [projectId]
  /// and nowhere else.
  const factory RunActionsState.completed({int? projectId, String? screenshot}) =
      RunActions$CompletedState;
}

/// What the widget picker of the Run tab shows: a pick that waits for a tap, the widget the user
/// picked (or the link of its chain the user switched to) and why the last pick or switch gave
/// nothing.
@freezed
abstract class RunPickState with _$RunPickState {
  const factory RunPickState({
    /// The project the picker is about; `null` before the first pick. A pick finished after the
    /// window moved to another project stays with this one.
    int? projectId,

    /// Whether the app waits for the user to tap a widget.
    @Default(false) bool picking,

    /// The widget the card shows, `chain[current]` read again with its own place, ancestors and
    /// screenshot; `null` before a widget was picked and after a pick that gave none.
    PickedWidget? widget,

    /// The widget picked in the app and the project's widgets around it, from it outwards. A
    /// switch to a link keeps the links inside it and reads the ones outside it again.
    @Default(<PickedAncestor>[]) List<PickedAncestor> chain,

    /// The index in [chain] of [widget].
    @Default(0) int current,

    /// Why the last pick or switch gave no widget: a [PickNoProjectWidget], a [PickGone] or a
    /// [PickFailed]; `null` when it gave one or was cancelled.
    PickResult? problem,
  }) = _RunPickState;
}

/// The buttons of the Run tab: start, stop, hot reload, hot restart, the widget picker, DevTools
/// and the screenshot.
///
/// One action at a time: a tap during another one is dropped — except Stop, which never waits
/// behind a reload or a screenshot that hangs. The run itself is observed through `RunController`.
///
/// Picking a widget is not one of those actions: it waits for a tap in the app without a limit, so
/// it runs beside them with its own state, [pick]. Stop, hot reload and hot restart cancel a pick
/// that waits and run at once.
final class RunActionsController extends StateController<RunActionsState>
    with DroppableControllerHandler {
  RunActionsController({
    required this._runRepository,
    required this._pickerRepository,
    super.initialState = const RunActionsState.initial(),
  });

  final IAppRunRepository _runRepository;
  final IWidgetPickerRepository _pickerRepository;
  final ValueNotifier<RunPickState> _pick = ValueNotifier<RunPickState>(const RunPickState());

  /// Changes with every pick, switch and cancel: a result that comes back after a newer one started
  /// (or after a cancel) is dropped.
  int _pickToken = 0;

  /// What the widget picker shows.
  ValueListenable<RunPickState> get pick => _pick;

  /// Starts the app of [projectId] on [device] with the selection the Run tab shows.
  void start(
    int projectId, {
    required Device device,
    required BuildMode mode,
    required String target,
    RunArguments arguments = const RunArguments(),
  }) => _run(
    projectId,
    () => _runRepository.start(
      projectId,
      device: device,
      mode: mode,
      target: target,
      arguments: arguments,
    ),
  );

  /// Stops the app; a pick that waits is cancelled. While another action is in progress the stop
  /// goes to the repository at once (ending the run also ends what that action waits for) and the
  /// state is left to that action; a failure is then logged.
  void stop(int projectId) {
    cancelPick(projectId);
    if (!isProcessing) return _run(projectId, () => _runRepository.stop(projectId));
    _runRepository.stop(projectId).catchError((Object error, StackTrace stackTrace) {
      l.w('RunActionsController | cannot stop the app of $projectId: $error', stackTrace);
    }).ignore();
  }

  /// Hot-reloads the app; a pick that waits is cancelled unless [cancelPick] is `false` (the
  /// reload after an agent turn: a hot reload keeps the isolate, select mode and the widget ids).
  void hotReload(int projectId, {bool cancelPick = true}) {
    if (isProcessing) return;
    if (cancelPick) this.cancelPick(projectId);
    _run(projectId, () => _runRepository.hotReload(projectId));
  }

  /// Hot-restarts the app; a pick that waits is cancelled.
  void hotRestart(int projectId) {
    if (isProcessing) return;
    cancelPick(projectId);
    _run(projectId, () => _runRepository.hotRestart(projectId));
  }

  /// Opens DevTools of the running app in the browser.
  void openDevTools(int projectId) => _run(projectId, () => _runRepository.openDevTools(projectId));

  /// Takes a screenshot of the running app; completes with the path of the PNG (relative to the
  /// project), or with `null` if the shot failed (the run's log says why).
  void screenshot(int projectId) => handle(() async {
    setState(const RunActionsState.inProgress());
    final path = await _runRepository.screenshot(projectId);
    setState(RunActionsState.completed(projectId: projectId, screenshot: path));
  }, error: (error, stackTrace) async => setState(RunActionsState.error(error: error)));

  /// Lets the user pick a widget in the app of [projectId]: [pick] waits until the user taps one,
  /// then shows it with its chain, or why there is none. A tap while a pick of the project waits is
  /// dropped; a pick of another project that waits is cancelled. Until it ends the card keeps the
  /// project's last widget, which a cancelled pick leaves in place.
  void pickWidget(int projectId) {
    if (isDisposed) return;
    final before = _pick.value;
    if (before.picking) {
      if (before.projectId == projectId) return;
      cancelPick(before.projectId!);
    }
    final kept = before.projectId == projectId ? before : const RunPickState();
    _setPick(kept.copyWith(projectId: projectId, picking: true, problem: null));
    _follow(projectId, () => _pickerRepository.pick(projectId), (now, result) {
      final idle = now.copyWith(picking: false);
      return switch (result) {
        PickPicked(:final widget) => RunPickState(
          projectId: projectId,
          widget: widget,
          chain: <PickedAncestor>[_link(widget), ...widget.ancestors],
        ),
        PickCancelled() => idle,
        PickNoProjectWidget() || PickGone() || PickFailed() => RunPickState(
          projectId: projectId,
          problem: result,
        ),
      };
    });
  }

  /// Switches the card of [projectId] to the link of its chain with inspector id [id]: the widget
  /// is read again with its ancestors and screenshot, and the links inside it stay. When the id was
  /// released (a new pick, a hot restart, a stop) the card keeps what it shows and says so. Does
  /// nothing while a pick waits.
  void selectAncestor(int projectId, String id) {
    final before = _pick.value;
    if (isDisposed || before.picking || before.projectId != projectId) return;
    _follow(projectId, () => _pickerRepository.select(projectId, id), (now, result) {
      switch (result) {
        case PickPicked(:final widget):
          final index = now.chain.indexWhere((link) => link.id == id);
          final inner = index < 0 ? const <PickedAncestor>[] : now.chain.sublist(0, index);
          return now.copyWith(
            widget: widget,
            chain: <PickedAncestor>[...inner, _link(widget), ...widget.ancestors],
            current: inner.length,
            problem: null,
          );
        case PickCancelled():
          return now;
        case PickNoProjectWidget() || PickGone() || PickFailed():
          return now.copyWith(problem: result);
      }
    });
  }

  /// Ends a pick of [projectId] that waits: the card goes back to what it showed before it, and the
  /// picker turns the select mode off in the app. Does nothing when none waits.
  void cancelPick(int projectId) {
    final pick = _pick.value;
    if (isDisposed || !pick.picking || pick.projectId != projectId) return;
    _pickToken++;
    _setPick(pick.copyWith(picking: false));
    _pickerRepository.cancel(projectId).catchError((Object error, StackTrace stackTrace) {
      l.w('RunActionsController | cannot cancel the pick of $projectId: $error', stackTrace);
    }).ignore();
  }

  /// Runs [call] beside the actions and shows what [apply] makes of its result, unless a newer
  /// pick, switch or cancel came first or the controller is gone. An error is a failed pick.
  void _follow(
    int projectId,
    Future<PickResult> Function() call,
    RunPickState Function(RunPickState now, PickResult result) apply,
  ) {
    final token = ++_pickToken;
    unawaited(() async {
      PickResult result;
      try {
        result = await call();
      } on Object catch (error, stackTrace) {
        l.w('RunActionsController | the picker failed for $projectId: $error', stackTrace);
        result = PickFailed(PickFailure.inspectorError, detail: '$error');
      }
      if (isDisposed || token != _pickToken) return;
      _setPick(apply(_pick.value, result));
    }());
  }

  /// [widget] as a link of the chain.
  static PickedAncestor _link(PickedWidget widget) => PickedAncestor(
    name: widget.name,
    file: widget.file,
    line: widget.line,
    column: widget.column,
    id: widget.id ?? '',
  );

  void _setPick(RunPickState value) {
    if (!isDisposed) _pick.value = value;
  }

  void _run(int projectId, Future<Object?> Function() action) => handle(() async {
    setState(const RunActionsState.inProgress());
    await action();
    setState(RunActionsState.completed(projectId: projectId));
  }, error: (error, stackTrace) async => setState(RunActionsState.error(error: error)));

  /// Cancels a pick that waits (the app leaves the select mode) and lets go of [pick].
  @override
  void dispose() {
    if (_pick.value case RunPickState(picking: true, :final projectId?)) cancelPick(projectId);
    _pickToken++;
    _pick.dispose();
    super.dispose();
  }
}
