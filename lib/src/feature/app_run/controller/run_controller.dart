import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/run_config_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/app_run_exceptions.dart';
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

    /// What the project (in a monorepo, the app at [appFolder]) adds to every `flutter run`: its
    /// saved flavor, defines and flags.
    @Default(RunArguments()) RunArguments arguments,

    /// The name of the `.vscode/launch.json` configuration the next start runs; `null` for Default
    /// ([target] and [arguments]).
    String? selectedConfig,

    /// What the last read of the project's `launch.json` gave; `null` before the first read.
    LaunchConfigs? launchConfigs,

    /// Whether the project is a monorepo (a pub workspace root without an app of its own): the Run
    /// tab then shows the App chip.
    @Default(false) bool monorepo,

    /// The folders of the Flutter apps of the monorepo (`apps/desktop`), in the order of the chip's
    /// menu; empty for a one-app project and for a monorepo without a Flutter app.
    @Default(<String>[]) List<String> apps,

    /// The folder of the app the App chip shows, relative to the project (`apps/desktop`); `''`
    /// for the project folder (a one-app project). [arguments] are this folder's.
    @Default('') String appFolder,

    /// Whether the selected configuration fixes [appFolder] with its `cwd`: the App chip cannot be
    /// changed while it is selected.
    @Default(false) bool appLocked,
  }) = _RunViewState;

  const RunViewState._();

  /// Whether the project is a monorepo with no app to run: none under `apps/` (or none selected
  /// yet) and no selected configuration fixes a folder. Nothing can start then.
  bool get noApp => monorepo && appFolder.isEmpty;
}

/// Follows the run, the output, the run arguments, the launch configurations and, in a monorepo,
/// the apps of one project at a time (the one open in the window).
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
  StreamSubscription<String?>? _selectedAppSubscription;
  StreamSubscription<LogEntry>? _logsSubscription;

  /// The app folder [_argumentsSubscription] follows.
  String _argumentsFolder = '';

  /// Whether the arguments of [_argumentsFolder] have arrived in the state.
  bool _argumentsArrived = false;

  /// The app the project has stored, which may be gone from disk; meaningful once
  /// [_storedAppArrived].
  String? _storedApp;

  /// Whether the stored app of this follow has arrived.
  bool _storedAppArrived = false;

  /// Whether the apps of this follow have been read.
  bool _appsRead = false;

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
  ///
  /// In a monorepo the apps are read and the stored app is selected, or the first app when none is
  /// stored or the stored one is gone; the arguments then are that app's.
  void watch(int projectId) => handle(() async {
    if (state.projectId == projectId && _runSubscription != null) return;
    await _cancel();
    _restorePending = true;
    _selectionArrived = false;
    _storedApp = null;
    _storedAppArrived = false;
    _appsRead = false;
    final deviceId = _deviceOverridden ? _userDeviceId : state.selectedDeviceId;
    _deviceOverridden = false;
    _modeOverridden = false;
    setState(RunViewState(projectId: projectId, selectedDeviceId: deviceId));
    _runSubscription = _repository.watchRun(projectId).listen((run) {
      if (state.projectId == projectId) setState(state.copyWith(run: run));
    });
    _followArguments(projectId, '');
    _selectedSubscription = _configRepository.watchSelected(projectId).listen((name) {
      if (state.projectId != projectId) return;
      _selectionArrived = true;
      setState(state.copyWith(selectedConfig: name));
      _dropVanished(projectId);
      _restoreChips(projectId);
      _resolveApp(projectId);
    });
    _selectedAppSubscription = _configRepository.watchSelectedApp(projectId).listen((folder) {
      if (state.projectId != projectId) return;
      _storedApp = folder;
      _storedAppArrived = true;
      _resolveApp(projectId);
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
    await _readApps(projectId);
  });

  /// Reads the `launch.json` and the apps of the current project again (the Run menu calls it
  /// before it opens). A selected configuration that is no longer in the file goes back to Default.
  Future<void> refreshConfigs() async {
    await handle(() async {
      final projectId = state.projectId;
      if (projectId == null) return;
      await _readConfigs(projectId);
      await _readApps(projectId);
    });
  }

  /// Chooses the app of the monorepo [projectId] (the project followed) the next start runs, by
  /// its [folder] (`apps/mobile`), and stores the choice; the arguments become that app's. Does
  /// nothing while the selected configuration fixes the app ([RunViewState.appLocked]) and for a
  /// folder that is not one of [RunViewState.apps].
  void chooseApp(int projectId, String folder) => handle(() async {
    if (state.projectId != projectId || state.appLocked || !state.apps.contains(folder)) return;
    _storedApp = folder;
    _storedAppArrived = true;
    _resolveApp(projectId);
    await _configRepository.saveSelectedApp(projectId, folder);
  });

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
    _resolveApp(projectId);
    await _configRepository.saveSelected(projectId, name);
  });

  /// What the next start of [projectId] (the project followed) passes to `flutter run` besides the
  /// device and the mode.
  ///
  /// Default is the chosen [RunViewState.target] with the arguments of the app, run in the app the
  /// App chip selects (the project folder in a one-app project). In a monorepo the apps are read
  /// again first, so an app deleted from disk is not run: the first app takes its place. A
  /// selected configuration is read from `launch.json` right now, so an edit of the file counts
  /// without the menu being opened; the start is then the configuration's own target, flavor,
  /// defines, flags and environment, without the Default arguments, in its `cwd` or else in the
  /// chip's app (see [RunStartArguments.fromLaunchConfig]). Its `deviceId` and
  /// `flutterMode` are not applied here: they switch the chips when the configuration is chosen
  /// ([chooseConfig]) or restored ([watch]), and the chips are the user's after that; the device
  /// and the mode of a start are the chips'. A configuration that is gone from the file starts
  /// Default and the choice goes back to Default.
  ///
  /// Before the apps of the follow are read they are read first, so a monorepo is known as one. A
  /// monorepo start without a folder to run in (no Flutter app under `apps/` and no configuration
  /// `cwd`) throws [RunNoAppException]: the workspace root has no app of its own.
  ///
  /// Throws [RunConfigNotStartable] when the configuration cannot run or the file cannot be read.
  Future<RunStartArguments> startArgumentsFor(int projectId) async {
    if (state.projectId != projectId) {
      throw StateError('RunController follows ${state.projectId}, not $projectId');
    }
    if (state.monorepo || !_appsRead) await _readApps(projectId);
    final start = await _startArguments(projectId);
    if (state.monorepo && start.appFolder.isEmpty) throw const RunNoAppException();
    return start;
  }

  /// [startArgumentsFor] once the apps are read: the Default start, or the selected configuration's.
  Future<RunStartArguments> _startArguments(int projectId) async {
    final name = state.selectedConfig;
    if (name == null) return _defaultStart(projectId);

    final configs = await _configRepository.launchConfigs(projectId);
    if (state.projectId == projectId) {
      setState(state.copyWith(launchConfigs: configs));
      _dropVanished(projectId);
      _resolveApp(projectId);
    }
    if (configs case final LaunchConfigsUnreadable unreadable) {
      throw RunConfigNotStartable.unreadable(name, unreadable);
    }
    final config = _configNamed(configs, name);
    if (config == null) return _defaultStart(projectId);
    if (config.unsupported case final reason?)
      throw RunConfigNotStartable.unsupported(name, reason);
    return RunStartArguments.fromLaunchConfig(config, appFolder: _chipApp());
  }

  /// The Default start of [projectId]: the chosen target and the arguments of the chip's app, read
  /// from the repository when the state does not hold them yet.
  Future<RunStartArguments> _defaultStart(int projectId) async {
    final folder = _chipApp();
    final arguments = _argumentsArrived && _argumentsFolder == folder
        ? state.arguments
        : await _configRepository.watch(projectId, appFolder: folder).first;
    return RunStartArguments(target: state.target, arguments: arguments, appFolder: folder);
  }

  /// Follows the arguments of the app at [folder] in [projectId] (`''` for the project folder),
  /// unless they are followed already. The arguments of the app before are dropped right away, so
  /// they never stand for the new app's.
  void _followArguments(int projectId, String folder) {
    if (_argumentsSubscription != null && _argumentsFolder == folder) return;
    _argumentsSubscription?.cancel().ignore();
    final switched = _argumentsSubscription != null;
    _argumentsFolder = folder;
    _argumentsArrived = false;
    if (switched) setState(state.copyWith(arguments: const RunArguments()));
    _argumentsSubscription = _configRepository.watch(projectId, appFolder: folder).listen((
      arguments,
    ) {
      if (state.projectId != projectId || _argumentsFolder != folder) return;
      _argumentsArrived = true;
      setState(state.copyWith(arguments: arguments));
    });
  }

  /// Reads whether [projectId] is a monorepo and its apps into the state, unless the window moved
  /// on meanwhile, then selects the app ([_resolveApp]).
  Future<void> _readApps(int projectId) async {
    final monorepo = await _configRepository.isMonorepo(projectId);
    final apps = monorepo ? await _configRepository.runnableApps(projectId) : const <String>[];
    if (state.projectId != projectId) return;
    _appsRead = true;
    setState(state.copyWith(monorepo: monorepo, apps: apps));
    _resolveApp(projectId);
  }

  /// The app the chip selects on its own: the stored one while it is one of the apps, else the
  /// first; `''` for a project without apps and until the apps and the stored app are both in.
  String _chipApp() {
    final apps = state.apps;
    if (!_appsRead || !_storedAppArrived || apps.isEmpty) return '';
    final stored = _storedApp;
    return stored != null && apps.contains(stored) ? stored : apps.first;
  }

  /// Sets the app of [projectId]: in a monorepo, the `cwd` of the selected configuration fixes it
  /// and locks the chip (also a `cwd` that is not an app, such as a plugin's `example`); otherwise
  /// it is the chip's own ([_chipApp]). The arguments follow it.
  void _resolveApp(int projectId) {
    if (state.projectId != projectId) return;
    final name = state.selectedConfig;
    final config = name == null ? null : _configNamed(state.launchConfigs, name);
    final cwd = state.monorepo && config != null && config.unsupported == null ? config.cwd : '';
    final locked = cwd.isNotEmpty;
    final folder = locked ? cwd : _chipApp();
    if (folder != state.appFolder || locked != state.appLocked) {
      setState(state.copyWith(appFolder: folder, appLocked: locked));
    }
    _followArguments(projectId, folder);
  }

  /// Reads the `launch.json` of [projectId] into the state, unless the window moved on meanwhile.
  Future<void> _readConfigs(int projectId) async {
    final configs = await _configRepository.launchConfigs(projectId);
    if (state.projectId != projectId) return;
    setState(state.copyWith(launchConfigs: configs));
    _dropVanished(projectId);
    _restoreChips(projectId);
    _resolveApp(projectId);
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
    await _selectedAppSubscription?.cancel();
    _runSubscription = null;
    _logsSubscription = null;
    _argumentsSubscription = null;
    _selectedSubscription = null;
    _selectedAppSubscription = null;
  }

  @override
  void dispose() {
    _runSubscription?.cancel().ignore();
    _logsSubscription?.cancel().ignore();
    _argumentsSubscription?.cancel().ignore();
    _selectedSubscription?.cancel().ignore();
    _selectedAppSubscription?.cancel().ignore();
    super.dispose();
  }
}
