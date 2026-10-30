import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'run_controller.freezed.dart';

/// What the Run tab shows for one project.
@freezed
abstract class RunViewState with _$RunViewState {
  const factory RunViewState({
    /// The project being followed; `null` before [RunController.watch].
    int? projectId,

    /// Where the project's run is.
    @Default(RunIdle()) RunState run,

    /// The newest [kRunLogLimit] lines of output.
    @Default(<LogEntry>[]) List<LogEntry> logs,

    /// The number of error lines among [logs].
    @Default(0) int errorCount,

    /// The device picked for the next start; `null` until the user picks one.
    String? selectedDeviceId,

    /// The build mode for the next start.
    @Default(BuildMode.debug) BuildMode mode,

    /// The entry point for the next start.
    @Default('lib/main.dart') String target,

    /// The widget the user last picked in the running app; cleared when the project changes.
    PickedWidget? picked,
  }) = _RunViewState;
}

/// Follows the run and the output of one project at a time (the one open in the window).
///
/// The buffer here is cleared on a project switch; the repository keeps the project's history and
/// replays it when the project is watched again.
final class RunController extends StateController<RunViewState> with SequentialControllerHandler {
  RunController({required this._repository, super.initialState = const RunViewState()});

  final IAppRunRepository _repository;
  StreamSubscription<RunState>? _runSubscription;
  StreamSubscription<LogEntry>? _logsSubscription;

  /// Per project: the newest line the user cleared; a replay never brings those back.
  final Map<int, int> _clearedThrough = <int, int>{};

  /// Follows [projectId]: drops the previous project's subscriptions, run and output. Calling it
  /// again for the same project changes nothing.
  ///
  /// The device is not chosen here: it stays `null` until [choose] sets it (the window picks the
  /// first running device once the devices are known, and never overrides a choice), and the chosen
  /// device survives a change of project. The mode and the target (a per-project path) go back to
  /// `debug` and `lib/main.dart`.
  void watch(int projectId) => handle(() async {
    if (state.projectId == projectId && _runSubscription != null) return;
    await _cancel();
    setState(RunViewState(projectId: projectId, selectedDeviceId: state.selectedDeviceId));
    _runSubscription = _repository.watchRun(projectId).listen((run) {
      if (state.projectId == projectId) setState(state.copyWith(run: run));
    });
    _logsSubscription = _repository.logs(projectId).listen((entry) {
      if (state.projectId != projectId || entry.seq <= (_clearedThrough[projectId] ?? -1)) return;
      final all = <LogEntry>[...state.logs, entry];
      final logs = all.length > kRunLogLimit ? all.sublist(all.length - kRunLogLimit) : all;
      setState(
        state.copyWith(
          logs: logs,
          errorCount: logs.where((log) => log.level == LogLevel.error).length,
        ),
      );
    });
  });

  /// Chooses what the next start uses; an argument left out keeps its value. (Not called `select`:
  /// `StateController` already has a method of that name.)
  void choose({String? deviceId, BuildMode? mode, String? target}) => setState(
    state.copyWith(
      selectedDeviceId: deviceId ?? state.selectedDeviceId,
      mode: mode ?? state.mode,
      target: target ?? state.target,
    ),
  );

  /// Remembers the widget picked in the app, so later actions do not lose it; `null` forgets it.
  void setPicked(PickedWidget? picked) => setState(state.copyWith(picked: picked));

  /// Empties the project's logs; lines that were already printed do not come back.
  void clearLogs() {
    final projectId = state.projectId;
    if (projectId != null && state.logs.isNotEmpty) {
      _clearedThrough[projectId] = state.logs.last.seq;
    }
    setState(state.copyWith(logs: const <LogEntry>[], errorCount: 0));
  }

  /// Marks the log line [seq] as sent to the agent, here and in the repository's buffer.
  void markSent(int seq) {
    setState(
      state.copyWith(
        logs: state.logs
            .map((log) => log.seq == seq ? log.copyWith(sentToAgent: true) : log)
            .toList(growable: false),
      ),
    );
    final projectId = state.projectId;
    if (projectId != null) _repository.markSent(projectId, seq).ignore();
  }

  Future<void> _cancel() async {
    await _runSubscription?.cancel();
    await _logsSubscription?.cancel();
    _runSubscription = null;
    _logsSubscription = null;
  }

  @override
  void dispose() {
    _runSubscription?.cancel().ignore();
    _logsSubscription?.cancel().ignore();
    super.dispose();
  }
}
