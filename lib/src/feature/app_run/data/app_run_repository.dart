import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_code_agent/src/common/flutter_daemon/daemon_connection.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/daemon_process.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_exceptions.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/run_output_parser.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/build_mode.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:l/l.dart' show l;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

export 'package:flutter_code_agent/src/feature/app_run/models/build_mode.dart';

/// How many of the newest log lines a project keeps (and replays to a new `logs` listener).
const int kRunLogLimit = 2000;

/// Runs a project's app (`flutter run`) and reports on it. Every method takes the project it is for.
abstract interface class IAppRunRepository {
  /// Whether the data is made up (the repository is a stand-in until the real one lands).
  bool get isPreview;

  /// The project's current [RunState] right away, then every change. Ends when the subscription is
  /// cancelled or the repository is disposed.
  Stream<RunState> watchRun(int projectId);

  /// The project's buffered output (at most [kRunLogLimit] newest lines, with their `sentToAgent`
  /// flags), then every new line, the same way [watchRun] replays the state. Ends when the
  /// subscription is cancelled or the repository is disposed.
  Stream<LogEntry> logs(int projectId);

  /// Flags the buffered line [seq] of the project as sent to the agent, so the flag survives a
  /// listener that leaves and comes back. Does nothing when the line is no longer buffered.
  Future<void> markSent(int projectId, int seq);

  /// Starts the app on [device] with the project's [arguments] and returns once the build began;
  /// follow it through [watchRun]. A running app is stopped and started again.
  Future<void> start(
    int projectId, {
    required Device device,
    required BuildMode mode,
    required String target,
    RunArguments arguments = const RunArguments(),
  });

  /// Stops the app. Does nothing when it is not running.
  Future<void> stop(int projectId);

  /// Hot-reloads the app and returns how long that took; [Duration.zero] when it is not running or
  /// the reload failed (the log says why).
  Future<Duration> hotReload(int projectId);

  /// Hot-restarts the app. Does nothing when it is not running; a failure is logged.
  Future<void> hotRestart(int projectId);

  /// Stops every run and closes every stream.
  Future<void> dispose();
}

/// {@template app_run_repository_impl}
/// Runs `flutter run --machine` per project and follows it over the daemon protocol: the events
/// become the [RunState], the output goes through a [RunOutputParser] into the log.
///
/// One run per project; a project's run never touches another's. Every process runs in its own
/// process group, and [stop] and [dispose] end the whole group.
/// {@endtemplate}
final class AppRunRepositoryImpl implements IAppRunRepository {
  /// {@macro app_run_repository_impl}
  ///
  /// [projectPath] gives the folder of a project (`null` when it is unknown), [flutter] the
  /// `flutter` executable for a project folder (`null` when there is no SDK). [stopTimeout] is how
  /// long a stopped app may take to exit before its process group is killed.
  AppRunRepositoryImpl({
    required this._projectPath,
    required this._flutter,
    required this._environment,
    this._start = startGroupedDaemonProcess,
    this._stopTimeout = const Duration(seconds: 5),
  });

  final Future<String?> Function(int projectId) _projectPath;
  final String? Function(String projectPath) _flutter;
  final Map<String, String> _environment;
  final DaemonProcessStarter _start;
  final Duration _stopTimeout;

  final Map<int, _ProjectRun> _runs = <int, _ProjectRun>{};
  bool _disposed = false;

  @override
  bool get isPreview => false;

  _ProjectRun _run(int projectId) => _runs.putIfAbsent(projectId, _ProjectRun.new);

  @override
  Stream<RunState> watchRun(int projectId) => _stream<RunState>(
    projectId,
    source: (run) => run.states.stream,
    initial: (run) => <RunState>[run.state],
  );

  @override
  Stream<LogEntry> logs(int projectId) => _stream<LogEntry>(
    projectId,
    source: (run) => run.logs.stream,
    initial: (run) => List<LogEntry>.of(run.buffer),
  );

  @override
  Future<void> markSent(int projectId, int seq) async {
    final buffer = _runs[projectId]?.buffer;
    if (buffer == null) return;
    final index = buffer.indexWhere((log) => log.seq == seq);
    if (index >= 0) buffer[index] = buffer[index].copyWith(sentToAgent: true);
  }

  /// A stream that first replays [initial] and then forwards [source]; it closes on cancel.
  Stream<T> _stream<T>(
    int projectId, {
    required Stream<T> Function(_ProjectRun run) source,
    required List<T> Function(_ProjectRun run) initial,
  }) {
    if (_disposed) return const Stream.empty();
    final run = _run(projectId);
    final controller = StreamController<T>();
    StreamSubscription<T>? subscription;
    controller
      ..onListen = () {
        initial(run).forEach(controller.add);
        subscription = source(run).listen(
          controller.add,
          onDone: () {
            if (!controller.isClosed) controller.close();
          },
        );
      }
      ..onCancel = () async {
        await subscription?.cancel();
        if (!controller.isClosed) await controller.close();
      };
    return controller.stream;
  }

  @override
  Future<void> start(
    int projectId, {
    required Device device,
    required BuildMode mode,
    required String target,
    RunArguments arguments = const RunArguments(),
  }) async {
    if (_disposed) return;
    final run = _run(projectId);
    final generation = ++run.generation;
    bool current() => !_disposed && run.generation == generation;

    if (run.launch case final previous?) await previous.stop();
    if (!current()) return;

    final path = await _projectPath(projectId);
    if (!current()) return;
    if (path == null || !io.Directory(path).existsSync()) {
      run.setState(
        const RunFailed(
          error: RunError(title: 'Project folder not found', message: ''),
        ),
      );
      return;
    }
    final flutter = _flutter(path);
    if (flutter == null) {
      run.setState(
        const RunFailed(
          error: RunError(title: 'Flutter SDK not found', message: ''),
        ),
      );
      return;
    }
    final packageName = _packageName(path);

    final flutterArgs = <String>[
      'run',
      '--machine',
      '-d',
      device.id,
      '--${mode.name}',
      '-t',
      target,
      ...arguments.toFlutterArgs(),
    ];
    late final _Launch launch;
    launch = _Launch(
      device: device,
      mode: mode,
      parser: RunOutputParser(projectRoot: path, packageName: packageName),
      stopTimeout: _stopTimeout,
      onState: (state) {
        if (run.launch == launch) run.setState(state);
      },
      onLog: (level, text, error) {
        if (run.launch == launch) run.log(level, text, error: error);
      },
      onDone: () {
        if (run.launch == launch) run.launch = null;
      },
    );
    run
      ..launch = launch
      ..setState(const RunBuilding())
      ..log(LogLevel.info, <String>[flutter, ...flutterArgs].map(_quote).join(' '));
    await launch.begin(
      () => _start(flutter, flutterArgs, workingDirectory: path, environment: _environment),
    );
  }

  @override
  Future<void> stop(int projectId) async {
    final run = _runs[projectId];
    if (run == null) return;
    // A start that has not spawned its process yet gives up.
    run.generation++;
    await run.launch?.stop();
  }

  @override
  Future<Duration> hotReload(int projectId) => _restart(projectId, full: false);

  @override
  Future<void> hotRestart(int projectId) => _restart(projectId, full: true);

  Future<Duration> _restart(int projectId, {required bool full}) async {
    final run = _runs[projectId];
    final launch = run?.launch;
    if (run == null || launch == null || run.state is! RunRunning) return Duration.zero;
    final title = full ? 'Hot restart failed' : 'Hot reload failed';
    final stopwatch = Stopwatch()..start();
    String message;
    try {
      final result = await launch.restart(full: full);
      stopwatch.stop();
      if (result is Map && result['code'] == 0) {
        final took = stopwatch.elapsed;
        launch.reloaded(took);
        return took;
      }
      message = result is Map ? '${result['message'] ?? ''}' : '$result';
    } on DaemonRequestException catch (error) {
      message = '${error.error}';
    } on Object catch (error) {
      l.w('AppRunRepository | ${full ? 'hot restart' : 'hot reload'} of $projectId failed: $error');
      message = '$error';
    }
    if (run.launch == launch) {
      run.log(
        LogLevel.error,
        message.isEmpty ? title : '$title: $message',
        error: RunError(title: title, message: message),
      );
    }
    return Duration.zero;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final runs = _runs.values.toList();
    _runs.clear();
    await Future.wait<void>(<Future<void>>[
      for (final run in runs)
        if (run.launch case final launch?) launch.stop(),
    ]);
    for (final run in runs) {
      await run.close();
    }
  }

  /// The `name:` of the project's `pubspec.yaml`, else the name of its folder.
  static String _packageName(String path) {
    try {
      final yaml = loadYaml(io.File(p.join(path, 'pubspec.yaml')).readAsStringSync());
      if (yaml case {'name': final String name}) return name;
    } on Object catch (error) {
      l.v('AppRunRepository | no package name in $path: $error');
    }
    return p.basename(path);
  }

  /// [argument] as a shell would need it: in single quotes when it holds a space or a quote.
  static String _quote(String argument) {
    if (argument.isNotEmpty && !argument.contains(RegExp(r'''[\s'"\\]'''))) return argument;
    return "'${argument.replaceAll("'", r"'\''")}'";
  }
}

/// What one project holds across its runs: the state, the output and the run in progress.
final class _ProjectRun {
  final StreamController<RunState> states = StreamController<RunState>.broadcast();
  final StreamController<LogEntry> logs = StreamController<LogEntry>.broadcast();

  /// The newest [kRunLogLimit] lines, replayed to a new `logs` listener.
  final List<LogEntry> buffer = <LogEntry>[];

  RunState state = const RunIdle();
  int nextSeq = 0;

  /// Changes with every start and stop, so a start that was overtaken gives up.
  int generation = 0;

  /// The `flutter run` of the project until it has ended.
  _Launch? launch;

  void setState(RunState value) {
    state = value;
    if (!states.isClosed) states.add(value);
  }

  void log(LogLevel level, String text, {RunError? error}) {
    final entry = LogEntry(
      seq: nextSeq++,
      time: DateTime.now(),
      level: level,
      text: text,
      error: error,
    );
    buffer.add(entry);
    if (buffer.length > kRunLogLimit) buffer.removeRange(0, buffer.length - kRunLogLimit);
    if (!logs.isClosed) logs.add(entry);
  }

  Future<void> close() async {
    await states.close();
    await logs.close();
  }
}

/// {@template launch}
/// One `flutter run --machine` process: it turns the daemon events into states and the output
/// into log lines, and reports the final state once the process has exited.
///
/// It reports through [onState] and [onLog]; the owner drops the reports of a launch that is no
/// longer current.
/// {@endtemplate}
final class _Launch {
  /// {@macro launch}
  _Launch({
    required this.device,
    required this.mode,
    required this.parser,
    required this.stopTimeout,
    required this.onState,
    required this.onLog,
    required this.onDone,
  });

  /// How many of the last error lines a failed build or a crashed app reports.
  static const int _errorLineLimit = 20;

  final Device device;
  final BuildMode mode;
  final RunOutputParser parser;
  final Duration stopTimeout;
  final void Function(RunState state) onState;
  final void Function(LogLevel level, String text, RunError? error) onLog;
  final void Function() onDone;

  final List<StreamSubscription<Object?>> _subscriptions = <StreamSubscription<Object?>>[];
  final ListQueue<String> _errorLines = ListQueue<String>();
  final Completer<void> _finished = Completer<void>();
  DaemonConnection? _connection;
  Future<void>? _shuttingDown;

  String? _appId;
  Uri? _vmServiceUri;
  Uri? _dtdUri;
  Uri? _devToolsUri;

  /// The running state once `app.started` came; `null` before.
  RunRunning? _running;

  /// Whether the user stopped the run.
  bool _stopping = false;

  /// Whether `flutter run` reported `app.stop`.
  bool _appStopped = false;

  /// The `error` of `app.stop`, if it had one.
  String? _stopError;

  /// Spawns the process with [spawn] and starts following it.
  Future<void> begin(Future<DaemonProcess> Function() spawn) async {
    final DaemonProcess process;
    try {
      process = await spawn();
    } on Object catch (error, stackTrace) {
      l.w('AppRunRepository | cannot start flutter run: $error', stackTrace);
      _finish(
        _stopping
            ? const RunStopped()
            : RunFailed(
                error: RunError(title: 'Build failed', message: '$error'),
              ),
      );
      return;
    }
    final connection = _connection = DaemonConnection(process);
    // Right away: the connection drops what nobody listens to.
    _subscriptions
      ..add(connection.events.listen(_onEvent))
      ..add(connection.output.listen((line) => _add(line.text, isError: line.isError)));
    unawaited(connection.done.then(_onExit, onError: (Object _) => _onExit(-1)));
    if (_stopping) unawaited(_shutDown());
  }

  /// Stops the app and completes once the process has exited.
  Future<void> stop() {
    _stopping = true;
    if (_connection != null) unawaited(_shutDown());
    return _finished.future;
  }

  /// Sends `app.restart`; returns its result. Throws when the daemon cannot answer.
  Future<Object?> restart({required bool full}) {
    final connection = _connection;
    final appId = _appId;
    if (connection == null || appId == null)
      throw const DaemonClosedException(method: 'app.restart');
    return connection.request('app.restart', <String, Object?>{
      'appId': appId,
      'fullRestart': full,
      'reason': 'manual',
    });
  }

  /// A hot reload or restart that took [took] has finished.
  void reloaded(Duration took) {
    final running = _running;
    if (running == null || _stopping) return;
    _setRunning(running.withReload(took));
  }

  /// Asks the app to stop (unless it already has), gives it [stopTimeout] to exit, then ends the
  /// process group.
  Future<void> _shutDown() => _shuttingDown ??= () async {
    final connection = _connection!;
    final askApp = _appId != null && !_appStopped;
    if (askApp) {
      connection.request('app.stop', <String, Object?>{'appId': _appId}).ignore();
    }
    if (askApp || _appStopped) {
      await connection.done.timeout(stopTimeout, onTimeout: () => -1);
    }
    await connection.close();
  }();

  void _onEvent(DaemonEvent event) {
    final params = event.params;
    switch (event.name) {
      case 'app.start':
        if (params['appId'] case final String appId) _appId = appId;
      case 'app.progress':
        if (_running == null && !_stopping && params['finished'] != true) {
          if (params['message'] case final String message) onState(RunBuilding(label: message));
        }
      case 'app.debugPort':
        _vmServiceUri = _uri(params['wsUri']) ?? _vmServiceUri;
        _addressesChanged();
      case 'app.dtd':
        _dtdUri = _uri(params['uri']) ?? _dtdUri;
        _addressesChanged();
      case 'app.devTools':
        _devToolsUri = _uri(params['uri']) ?? _devToolsUri;
        _addressesChanged();
      case 'app.started':
        if (_running != null) return;
        final running = RunRunning(
          device: device,
          startedAt: DateTime.now(),
          mode: mode,
          vmServiceUri: _vmServiceUri,
          dtdUri: _dtdUri,
          devToolsUri: _devToolsUri,
        );
        _running = running;
        if (!_stopping) onState(running);
      case 'app.log':
        if (params['log'] case final String log) _add(log, isError: params['error'] == true);
      case 'daemon.logMessage':
        if (params['message'] case final String message) {
          _add(message, isError: params['level'] == 'error');
        }
      case 'app.stop':
        _appStopped = true;
        if (params['error'] case final Object error) _stopError = '$error';
        if (_connection != null) unawaited(_shutDown());
    }
  }

  void _addressesChanged() {
    final running = _running;
    if (running == null || _stopping) return;
    _setRunning(
      running.copyWith(vmServiceUri: _vmServiceUri, dtdUri: _dtdUri, devToolsUri: _devToolsUri),
    );
  }

  void _setRunning(RunRunning running) {
    _running = running;
    onState(running);
  }

  static Uri? _uri(Object? value) => value is String ? Uri.tryParse(value) : null;

  /// Feeds [text] — possibly several lines — to the parser.
  void _add(String text, {required bool isError}) {
    final lines = text.isEmpty ? const <String>[''] : const LineSplitter().convert(text);
    for (final line in lines) {
      parser.add(line, isError: isError).forEach(_emit);
    }
  }

  void _emit(ParsedLine line) {
    if (line.level == LogLevel.error) {
      _errorLines.add(line.text);
      if (_errorLines.length > _errorLineLimit) _errorLines.removeFirst();
    }
    onLog(line.level, line.text, line.error);
  }

  void _onExit(int code) {
    parser.flush().forEach(_emit);
    final RunState state;
    if (_stopping) {
      state = const RunStopped();
    } else if (_running == null) {
      state = RunFailed(
        error:
            parser.firstBuildError ??
            RunError(title: 'Build failed', message: _stopError ?? _lastErrors(code)),
      );
    } else if (code == 0 && _stopError == null) {
      state = const RunStopped();
    } else {
      state = RunFailed(
        error: RunError(title: 'App exited', message: _stopError ?? _lastErrors(code)),
      );
    }
    _finish(state);
  }

  String _lastErrors(int code) =>
      _errorLines.isEmpty ? 'flutter run exited with code $code.' : _errorLines.join('\n');

  void _finish(RunState state) {
    if (_finished.isCompleted) return;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    onState(state);
    onDone();
    _finished.complete();
  }
}
