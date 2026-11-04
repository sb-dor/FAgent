import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/launch_config_reader.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/run_config_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/launch_config.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_start_arguments.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:l/l.dart' show l;

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

    /// What the project adds to every `flutter run`: its saved flavor, defines and flags.
    @Default(RunArguments()) RunArguments arguments,

    /// The name of the `.vscode/launch.json` configuration the next start runs; `null` for Default
    /// ([target] and [arguments]).
    String? selectedConfig,

    /// What the last read of the project's `launch.json` gave; `null` before the first read.
    LaunchConfigs? launchConfigs,
  }) = _RunViewState;
}

/// Follows the run, the output, the run arguments and the launch configurations of one project at
/// a time (the one open in the window).
///
/// The buffer here is cleared on a project switch; the repository keeps the project's history and
/// replays it when the project is watched again.
final class RunController extends StateController<RunViewState> with SequentialControllerHandler {
  RunController({
    required this._repository,
    required this._configRepository,
    super.initialState = const RunViewState(),
  });

  final IAppRunRepository _repository;
  final IRunConfigRepository _configRepository;
  StreamSubscription<RunState>? _runSubscription;
  StreamSubscription<RunArguments>? _argumentsSubscription;
  StreamSubscription<String?>? _selectedSubscription;
  StreamSubscription<LogEntry>? _logsSubscription;

  /// Per project: the newest line the user cleared; a replay never brings those back.
  final Map<int, int> _clearedThrough = <int, int>{};

  /// Follows [projectId]: drops the previous project's subscriptions, run and output. Calling it
  /// again for the same project changes nothing.
  ///
  /// The device is not chosen here: it stays `null` until [choose] sets it (the window picks the
  /// first running device once the devices are known, and never overrides a choice), and the chosen
  /// device survives a change of project. The mode and the target (a per-project path) go back to
  /// `debug` and `lib/main.dart`. The project's selected configuration and its `launch.json` are
  /// read.
  void watch(int projectId) => handle(() async {
    if (state.projectId == projectId && _runSubscription != null) return;
    await _cancel();
    setState(RunViewState(projectId: projectId, selectedDeviceId: state.selectedDeviceId));
    _runSubscription = _repository.watchRun(projectId).listen((run) {
      if (state.projectId == projectId) setState(state.copyWith(run: run));
    });
    _argumentsSubscription = _configRepository.watch(projectId).listen((arguments) {
      if (state.projectId == projectId) setState(state.copyWith(arguments: arguments));
    });
    _selectedSubscription = _configRepository.watchSelected(projectId).listen((name) {
      if (state.projectId != projectId) return;
      setState(state.copyWith(selectedConfig: name));
      _dropVanished(projectId);
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
    await _readConfigs(projectId);
  });

  /// Reads the `launch.json` of the current project again (the Run menu calls it before it opens).
  /// A selected configuration that is no longer in the file goes back to Default.
  Future<void> refreshConfigs() async {
    await handle(() async {
      final projectId = state.projectId;
      if (projectId != null) await _readConfigs(projectId);
    });
  }

  /// Chooses the configuration the next start runs, by [name]; `null` is Default. The choice is
  /// stored for the project. A configuration with a device or a mode switches the chips to them
  /// ([choose]); the chips stay the user's to change after that. Of two configurations with the
  /// same name the first counts.
  void chooseConfig(String? name) => handle(() async {
    final projectId = state.projectId;
    if (projectId == null) return;
    setState(state.copyWith(selectedConfig: name));
    final config = name == null ? null : _configNamed(state.launchConfigs, name);
    if (config != null && (config.deviceId != null || config.mode != null)) {
      choose(deviceId: config.deviceId, mode: config.mode);
    }
    await _configRepository.saveSelected(projectId, name);
  });

  /// What the next start of [projectId] (the project followed) passes to `flutter run` besides the
  /// device and the mode.
  ///
  /// Default is the chosen [RunViewState.target] with the project's [RunViewState.arguments]. A
  /// selected configuration is read from `launch.json` right now, so an edit of the file counts
  /// without the menu being opened; the start is then the configuration's own target, flavor,
  /// defines, flags and environment, without the Default arguments. A configuration that is gone
  /// from the file starts Default and the choice goes back to Default.
  ///
  /// Throws [RunConfigNotStartable] when the configuration cannot run or the file cannot be read.
  Future<RunStartArguments> startArgumentsFor(int projectId) async {
    if (state.projectId != projectId) {
      throw StateError('RunController follows ${state.projectId}, not $projectId');
    }
    final defaults = RunStartArguments(target: state.target, arguments: state.arguments);
    final name = state.selectedConfig;
    if (name == null) return defaults;

    final configs = await _configRepository.launchConfigs(projectId);
    if (state.projectId == projectId) {
      setState(state.copyWith(launchConfigs: configs));
      _dropVanished(projectId);
    }
    if (configs case final LaunchConfigsUnreadable unreadable) {
      throw RunConfigNotStartable.unreadable(name, unreadable);
    }
    final config = _configNamed(configs, name);
    if (config == null) return defaults;
    if (config.unsupported case final reason?) throw RunConfigNotStartable.unsupported(name, reason);
    return RunStartArguments.fromLaunchConfig(config);
  }

  /// Reads the `launch.json` of [projectId] into the state, unless the window moved on meanwhile.
  Future<void> _readConfigs(int projectId) async {
    final configs = await _configRepository.launchConfigs(projectId);
    if (state.projectId != projectId) return;
    setState(state.copyWith(launchConfigs: configs));
    _dropVanished(projectId);
  }

  /// Goes back to Default when the selected configuration is not in the file read last (or there
  /// is no file). A file that cannot be read keeps the choice: it may be in the middle of an edit.
  void _dropVanished(int projectId) {
    final name = state.selectedConfig;
    if (state.projectId != projectId || name == null) return;
    final gone = switch (state.launchConfigs) {
      LaunchConfigsMissing() => true,
      final LaunchConfigsRead read => _configNamed(read, name) == null,
      LaunchConfigsUnreadable() || null => false,
    };
    if (!gone) return;
    setState(state.copyWith(selectedConfig: null));
    _configRepository.saveSelected(projectId, null).catchError((Object error, StackTrace stack) {
      l.w('RunController | cannot store Default for $projectId: $error', stack);
    }).ignore();
  }

  /// The first configuration called [name] in [configs].
  static LaunchConfig? _configNamed(LaunchConfigs? configs, String name) => switch (configs) {
    LaunchConfigsRead(:final configs) => configs.where((config) => config.name == name).firstOrNull,
    _ => null,
  };

  /// Chooses what the next start uses; an argument left out keeps its value. (Not called `select`:
  /// `StateController` already has a method of that name.)
  void choose({String? deviceId, BuildMode? mode, String? target}) => setState(
    state.copyWith(
      selectedDeviceId: deviceId ?? state.selectedDeviceId,
      mode: mode ?? state.mode,
      target: target ?? state.target,
    ),
  );

  /// Forgets the chosen device, for when it is gone and there is none to take its place.
  void clearDevice() => setState(state.copyWith(selectedDeviceId: null));

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
    await _argumentsSubscription?.cancel();
    await _selectedSubscription?.cancel();
    _runSubscription = null;
    _logsSubscription = null;
    _argumentsSubscription = null;
    _selectedSubscription = null;
  }

  @override
  void dispose() {
    _runSubscription?.cancel().ignore();
    _logsSubscription?.cancel().ignore();
    _argumentsSubscription?.cancel().ignore();
    _selectedSubscription?.cancel().ignore();
    super.dispose();
  }
}
