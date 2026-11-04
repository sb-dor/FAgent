import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
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

  /// Whether this follow still has to switch the chips to the restored configuration: set by
  /// [watch], done once the stored selection and the first read of the file are both in.
  bool _restorePending = false;

  /// Whether the stored selection of this follow has arrived.
  bool _selectionArrived = false;

  /// Per project: the newest line the user cleared; a replay never brings those back.
  final Map<int, int> _clearedThrough = <int, int>{};

  /// Whether the device chip shows a configuration's device rather than the user's own.
  bool _deviceOverridden = false;

  /// The device the user had before a configuration switched the chip; meaningful while
  /// [_deviceOverridden].
  String? _userDeviceId;

  /// Whether the mode chip shows a configuration's mode rather than the user's own.
  bool _modeOverridden = false;

  /// The mode the user had before a configuration switched the chip; meaningful while
  /// [_modeOverridden].
  BuildMode _userMode = BuildMode.debug;

  /// Follows [projectId]: drops the previous project's subscriptions, run and output. Calling it
  /// again for the same project changes nothing.
  ///
  /// The device is not chosen here: it stays `null` until [choose] sets it (the window picks the
  /// first running device once the devices are known, and never overrides a choice), and the chosen
  /// device survives a change of project; a device a configuration of the previous project set is
  /// not carried over: the user's own comes back. The mode and the target (a per-project path) go
  /// back to `debug` and `lib/main.dart`. The project's selected configuration and its
  /// `launch.json` are read; once both are in, a selected configuration with a device or a mode
  /// switches the chips to them, once for this follow (later reads leave the chips to the user).
  void watch(int projectId) => handle(() async {
    if (state.projectId == projectId && _runSubscription != null) return;
    await _cancel();
    _restorePending = true;
    _selectionArrived = false;
    final deviceId = _deviceOverridden ? _userDeviceId : state.selectedDeviceId;
    _deviceOverridden = false;
    _modeOverridden = false;
    setState(RunViewState(projectId: projectId, selectedDeviceId: deviceId));
    _runSubscription = _repository.watchRun(projectId).listen((run) {
      if (state.projectId == projectId) setState(state.copyWith(run: run));
    });
    _argumentsSubscription = _configRepository.watch(projectId).listen((arguments) {
      if (state.projectId == projectId) setState(state.copyWith(arguments: arguments));
    });
    _selectedSubscription = _configRepository.watchSelected(projectId).listen((name) {
      if (state.projectId != projectId) return;
      _selectionArrived = true;
      setState(state.copyWith(selectedConfig: name));
      _dropVanished(projectId);
      _restoreChips(projectId);
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
  /// stored for the project. A configuration with a device or a mode switches the chips to them;
  /// the chips stay the user's to change after that. A chip the previous configuration switched and
  /// this one does not set (or Default) goes back to what the user had ([_applyConfigChips]). Of
  /// two configurations with the same name the first counts.
  void chooseConfig(String? name) => handle(() async {
    final projectId = state.projectId;
    if (projectId == null) return;
    // The user's choice replaces the restored one.
    _restorePending = false;
    setState(state.copyWith(selectedConfig: name));
    _applyConfigChips(name == null ? null : _configNamed(state.launchConfigs, name));
    await _configRepository.saveSelected(projectId, name);
  });

  /// What the next start of [projectId] (the project followed) passes to `flutter run` besides the
  /// device and the mode.
  ///
  /// Default is the chosen [RunViewState.target] with the project's [RunViewState.arguments]. A
  /// selected configuration is read from `launch.json` right now, so an edit of the file counts
  /// without the menu being opened; the start is then the configuration's own target, flavor,
  /// defines, flags and environment, without the Default arguments. Its `deviceId` and
  /// `flutterMode` are not applied here: they switch the chips when the configuration is chosen
  /// ([chooseConfig]) or restored ([watch]), and the chips are the user's after that; the device
  /// and the mode of a start are the chips'. A configuration that is gone from the file starts
  /// Default and the choice goes back to Default.
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
    if (config.unsupported case final reason?)
      throw RunConfigNotStartable.unsupported(name, reason);
    return RunStartArguments.fromLaunchConfig(config);
  }

  /// Reads the `launch.json` of [projectId] into the state, unless the window moved on meanwhile.
  Future<void> _readConfigs(int projectId) async {
    final configs = await _configRepository.launchConfigs(projectId);
    if (state.projectId != projectId) return;
    setState(state.copyWith(launchConfigs: configs));
    _dropVanished(projectId);
    _restoreChips(projectId);
  }

  /// Switches the chips to the device and the mode of the restored configuration, once per
  /// [watch]: when the stored selection and the first read of the file are both in. Only the fields
  /// the configuration sets change.
  void _restoreChips(int projectId) {
    if (!_restorePending || state.projectId != projectId) return;
    if (!_selectionArrived || state.launchConfigs == null) return;
    _restorePending = false;
    final name = state.selectedConfig;
    _applyConfigChips(name == null ? null : _configNamed(state.launchConfigs, name));
  }

  /// Switches the chips to the device and the mode [config] sets, remembering what the user had
  /// before; a chip the previous configuration switched and [config] (`null` for Default) does not
  /// set goes back to the user's value. As in VS Code, a configuration's device and mode last only
  /// while it is selected.
  void _applyConfigChips(LaunchConfig? config) {
    var deviceId = state.selectedDeviceId;
    var mode = state.mode;
    if (config?.deviceId case final configDevice?) {
      if (!_deviceOverridden) _userDeviceId = deviceId;
      _deviceOverridden = true;
      deviceId = configDevice;
    } else if (_deviceOverridden) {
      _deviceOverridden = false;
      deviceId = _userDeviceId;
    }
    if (config?.mode case final configMode?) {
      if (!_modeOverridden) _userMode = mode;
      _modeOverridden = true;
      mode = configMode;
    } else if (_modeOverridden) {
      _modeOverridden = false;
      mode = _userMode;
    }
    if (deviceId == state.selectedDeviceId && mode == state.mode) return;
    setState(state.copyWith(selectedDeviceId: deviceId, mode: mode));
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

  /// Chooses what the next start uses; an argument left out keeps its value. A chip chosen while
  /// a configuration has switched it is the user's again: it stays when the configuration is left.
  /// (Not called `select`: `StateController` already has a method of that name.)
  void choose({String? deviceId, BuildMode? mode, String? target}) {
    if (deviceId != null) _deviceOverridden = false;
    if (mode != null) _modeOverridden = false;
    setState(
      state.copyWith(
        selectedDeviceId: deviceId ?? state.selectedDeviceId,
        mode: mode ?? state.mode,
        target: target ?? state.target,
      ),
    );
  }

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
