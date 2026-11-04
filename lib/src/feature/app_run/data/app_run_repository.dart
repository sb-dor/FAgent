import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flutter_code_agent/src/common/flutter_daemon/daemon_connection.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/daemon_process.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_exceptions.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_executable.dart';
import 'package:flutter_code_agent/src/common/utils/url_opener.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/flutter_error_listener.dart';
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

/// How many characters of one output line the log keeps; the rest of a longer line (one huge
/// `print`) is left out and counted.
const int kLogLineLimit = 16 * 1024;

/// Runs a project's app (`flutter run`) and reports on it. Every method takes the project it is for.
abstract interface class IAppRunRepository {
  /// Whether the data is made up (the repository is a stand-in until the real one lands).
  bool get isPreview;

  /// The project's current [RunState] right away, then every change. Ends when the subscription is
  /// cancelled or the repository is disposed.
  Stream<RunState> watchRun(int projectId);

  /// The project's [RunState] right now; [RunIdle] for a project that never ran.
  RunState currentRun(int projectId);

  /// The newest [limit] output lines of the project's current run right now, oldest first: the
  /// lines from its last start on (the last run's, while none is active), not those of runs
  /// before. [logs] still replays the whole buffer.
  List<LogEntry> recentLogs(int projectId, {int limit = kRunLogLimit});

  /// The project's buffered output (at most [kRunLogLimit] newest lines, with their `sentToAgent`
  /// flags), then every new line, the same way [watchRun] replays the state. Ends when the
  /// subscription is cancelled or the repository is disposed.
  Stream<LogEntry> logs(int projectId);

  /// Flags the buffered line [seq] of the project as sent to the agent, so the flag survives a
  /// listener that leaves and comes back. Does nothing when the line is no longer buffered.
  Future<void> markSent(int projectId, int seq);

  /// Starts the app on [device] with the project's [arguments] and returns once the build began;
  /// follow it through [watchRun]. A running app is stopped and started again. `flutter run` runs
  /// in the project folder; [environment] is added over the app's own environment.
  Future<void> start(
    int projectId, {
    required Device device,
    required BuildMode mode,
    required String target,
    RunArguments arguments = const RunArguments(),
    Map<String, String> environment = const <String, String>{},
  });

  /// Stops the app. Does nothing when it is not running.
  Future<void> stop(int projectId);

  /// Hot-reloads the app and returns how long that took; [Duration.zero] when it is not running or
  /// the reload failed (the log says why).
  Future<Duration> hotReload(int projectId);

  /// Hot-restarts the app and returns how long that took; [Duration.zero] when it is not running
  /// or the restart failed (the log says why).
  Future<Duration> hotRestart(int projectId);

  /// Opens DevTools of the running app in the browser. Does nothing until `flutter run` has
  /// reported the DevTools address (see [RunRunning.devToolsUri]); a failure is logged.
  Future<void> openDevTools(int projectId);

  /// Takes a screenshot of the running app through the widget inspector, saves it as a PNG in the
  /// project and returns its path relative to the project folder. `null` when the app is not
  /// running or was not started in debug mode (the inspector exists only there), and when the shot
  /// failed (the log says why).
  Future<String?> screenshot(int projectId);

  /// Stops every run and closes every stream.
  Future<void> dispose();
}

/// Where the screenshots of a project go, relative to the project folder.
const String kScreenshotsFolder = '.dart_tool/flutter_code_agent/screenshots';

/// How many of the newest screenshots a project keeps.
const int kScreenshotLimit = 20;

/// Writes [bytes] to a new PNG in the screenshot folder of the project at [root] and returns its path
/// relative to [root]. The file is `<name>.png`, or `<name>-2.png` and so on when that exists.
/// Then drops all but the newest [kScreenshotLimit] shots of the folder: the app's
/// (`screenshot-…`) and the widget picker's (`widget-…`) together; other files are left alone.
Future<String> saveScreenshotPng(String root, List<int> bytes, {required String name}) async {
  final folder = io.Directory(p.join(root, kScreenshotsFolder));
  await folder.create(recursive: true);
  var unique = name;
  for (var n = 2; io.File(p.join(folder.path, '$unique.png')).existsSync(); n++) {
    unique = '$name-$n';
  }
  final file = io.File(p.join(folder.path, '$unique.png'));
  await file.writeAsBytes(bytes, flush: true);
  try {
    final shots =
        <({String path, DateTime modified})>[
            await for (final entity in folder.list())
              if (entity is io.File && _shotName.hasMatch(p.basename(entity.path)))
                (path: entity.path, modified: entity.lastModifiedSync()),
          ]
          // Oldest first; the name orders shots of the same moment (the app's carry a time stamp).
          ..sort((a, b) {
            final byTime = a.modified.compareTo(b.modified);
            return byTime != 0 ? byTime : a.path.compareTo(b.path);
          });
    for (final old in shots.take(math.max(0, shots.length - kScreenshotLimit))) {
      if (old.path != file.path) await io.File(old.path).delete();
    }
  } on io.FileSystemException catch (error) {
    l.w('Screenshots | cannot prune the screenshots in ${folder.path}: $error');
  }
  return p.posix.join(kScreenshotsFolder, '$unique.png');
}

/// The shots [saveScreenshotPng] counts toward [kScreenshotLimit].
final RegExp _shotName = RegExp(r'^(screenshot|widget)-.+\.png$');

/// {@template app_run_repository_impl}
/// Runs `flutter run --machine` per project and follows it over the daemon protocol: the events
/// become the [RunState], the output goes through a [RunOutputParser] into the log.
///
/// A debug run's Flutter errors come from its VM service (`Flutter.Error`, through an
/// [IFlutterErrorListener]) once that is connected: with structured errors on, the framework no
/// longer prints them. Without the connection (profile, release, a failed connect) the error
/// blocks of the output are parsed instead.
///
/// One run per project; a project's run never touches another's. Every process runs in its own
/// process group, and [stop] and [dispose] end the whole group.
/// {@endtemplate}
final class AppRunRepositoryImpl implements IAppRunRepository {
  /// {@macro app_run_repository_impl}
  ///
  /// [projectPath] gives the folder of a project (`null` when it is unknown), [flutter] the
  /// `flutter` executable for a project folder (`null` when there is no SDK). [stopTimeout] is how
  /// long a stopped app may take to exit before its process group is killed, [restartTimeout] how
  /// long a hot reload or restart may take before it counts as failed. [openUrl] opens DevTools in
  /// the browser, [now] names the screenshots. [connectErrors] connects to the VM service of a
  /// debug run for its runtime errors.
  AppRunRepositoryImpl({
    required this._projectPath,
    required this._flutter,
    required this._environment,
    this._start = startGroupedDaemonProcess,
    this._stopTimeout = const Duration(seconds: 5),
    this._restartTimeout = const Duration(seconds: 30),
    this._openUrl = openUrl,
    this._now = DateTime.now,
    this._connectErrors = FlutterErrorListener.connect,
  });

  final Future<String?> Function(int projectId) _projectPath;
  final String? Function(String projectPath) _flutter;
  final Map<String, String> _environment;
  final DaemonProcessStarter _start;
  final Duration _stopTimeout;
  final Duration _restartTimeout;
  final UrlOpener _openUrl;
  final DateTime Function() _now;
  final FlutterErrorListenerConnect _connectErrors;

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
  RunState currentRun(int projectId) => _runs[projectId]?.state ?? const RunIdle();

  @override
  List<LogEntry> recentLogs(int projectId, {int limit = kRunLogLimit}) {
    final run = _runs[projectId];
    if (run == null) return const <LogEntry>[];
    final ofRun = run.buffer.where((entry) => entry.seq >= run.runStartSeq).toList();
    return ofRun.sublist(math.max(0, ofRun.length - math.max(0, limit)));
  }

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
    Map<String, String> environment = const <String, String>{},
  }) async {
    if (_disposed) return;
    final run = _run(projectId);
    final generation = ++run.generation;
    bool current() => !_disposed && run.generation == generation;

    if (run.launch case final previous?) await previous.stop();
    if (!current()) return;

    // The lines the previous launch logged while it stopped belong to it.
    run.runStartSeq = run.nextSeq;
    final path = await _projectPath(projectId);
    if (!current()) return;
    if (path == null || !io.Directory(path).existsSync()) {
      run.setState(
        RunFailed(
          error: RunError(
            title: 'Project folder not found',
            message: path == null
                ? 'The folder of this project is unknown.'
                : '$path does not exist.',
          ),
        ),
      );
      return;
    }
    final flutter = _flutter(path);
    if (flutter == null) {
      run.setState(
        RunFailed(
          error: RunError(title: 'Flutter SDK not found', message: flutterNotFoundMessage(path)),
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
      parser: RunOutputParser(
        projectRoot: path,
        resolvedProjectRoot: _resolved(path),
        packageName: packageName,
      ),
      connectErrors: _connectErrors,
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
      () => _start(
        flutter,
        flutterArgs,
        workingDirectory: path,
        environment: environment.isEmpty
            ? _environment
            : <String, String>{..._environment, ...environment},
      ),
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
  Future<Duration> hotRestart(int projectId) => _restart(projectId, full: true);

  Future<Duration> _restart(int projectId, {required bool full}) async {
    final run = _runs[projectId];
    final launch = run?.launch;
    if (run == null || launch == null || run.state is! RunRunning) return Duration.zero;
    final title = full ? 'Hot restart failed' : 'Hot reload failed';
    final stopwatch = Stopwatch()..start();
    String message;
    try {
      final result = await launch.restart(full: full).timeout(_restartTimeout);
      stopwatch.stop();
      if (result is Map && result['code'] == 0) {
        final took = stopwatch.elapsed;
        launch.reloaded(took);
        return took;
      }
      message = result is Map ? '${result['message'] ?? ''}' : '$result';
    } on DaemonRequestException catch (error) {
      message = '${error.error}';
    } on TimeoutException {
      message = 'timed out';
    } on Object catch (error) {
      l.w('AppRunRepository | ${full ? 'hot restart' : 'hot reload'} of $projectId failed: $error');
      message = '$error';
    }
    _logFailure(run, launch, title, message);
    return Duration.zero;
  }

  @override
  Future<void> openDevTools(int projectId) async {
    final run = _runs[projectId];
    final launch = run?.launch;
    if (run == null || launch == null) return;
    if (run.state case RunRunning(:final devToolsUri?, :final vmServiceUri)) {
      try {
        await _openUrl(_devToolsUrl(devToolsUri, vmServiceUri));
      } on Object catch (error, stackTrace) {
        l.w('AppRunRepository | cannot open DevTools of $projectId: $error', stackTrace);
        _logFailure(run, launch, 'Opening DevTools failed', '$error');
      }
    }
  }

  /// The address of DevTools for the app: [devTools] as `flutter run` reported it, with the VM
  /// service of the app added when the address does not name one.
  static Uri _devToolsUrl(Uri devTools, Uri? vmService) {
    if (vmService == null || devTools.queryParameters.containsKey('uri')) return devTools;
    return devTools.replace(
      path: devTools.path.isEmpty ? '/' : devTools.path,
      query: '${devTools.hasQuery ? '${devTools.query}&' : ''}uri=$vmService',
    );
  }

  @override
  Future<String?> screenshot(int projectId) async {
    final run = _runs[projectId];
    final launch = run?.launch;
    final state = run?.state;
    if (run == null || launch == null || state is! RunRunning || state.mode != BuildMode.debug) {
      return null;
    }
    const title = 'Screenshot failed';
    try {
      final root = await _projectPath(projectId);
      if (root == null) throw StateError('The project folder is unknown.');
      final bytes = await launch.screenshot();
      return await saveScreenshotPng(root, bytes, name: 'screenshot-${_stamp(_now())}');
    } on DaemonRequestException catch (error) {
      _logFailure(run, launch, title, '${error.error}');
    } on Object catch (error, stackTrace) {
      l.w('AppRunRepository | screenshot of $projectId failed: $error', stackTrace);
      _logFailure(run, launch, title, '$error');
    }
    return null;
  }

  /// `yyyyMMdd-HHmmss`.
  static String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year.toString().padLeft(4, '0')}${two(time.month)}${two(time.day)}'
        '-${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }

  /// Logs an error line with a [RunError] of [title], unless [launch] is no longer the run's.
  void _logFailure(_ProjectRun run, _Launch launch, String title, String message) {
    if (run.launch != launch) return;
    run.log(
      LogLevel.error,
      message.isEmpty ? title : '$title: $message',
      error: RunError(title: title, message: message),
    );
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

  /// [path] with its symbolic links resolved; `null` when that fails.
  static String? _resolved(String path) {
    try {
      return io.Directory(path).resolveSymbolicLinksSync();
    } on io.FileSystemException catch (error) {
      l.v('AppRunRepository | cannot resolve $path: $error');
      return null;
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

  /// The [LogEntry.seq] of the first line of the current run: the lines before it belong to
  /// earlier runs.
  int runStartSeq = 0;

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
    required this.connectErrors,
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
  final FlutterErrorListenerConnect connectErrors;
  final Duration stopTimeout;
  final void Function(RunState state) onState;
  final void Function(LogLevel level, String text, RunError? error) onLog;
  final void Function() onDone;

  final List<StreamSubscription<Object?>> _subscriptions = <StreamSubscription<Object?>>[];
  final ListQueue<String> _errorLines = ListQueue<String>();
  final Completer<void> _finished = Completer<void>();
  DaemonConnection? _connection;
  Future<void>? _shuttingDown;

  /// The Flutter errors of the app from its VM service, once connected.
  IFlutterErrorListener? _errorListener;

  /// Whether the launch has tried to connect [_errorListener]: it tries once.
  bool _errorListenerTried = false;

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

  /// Whether the process has exited.
  bool _exited = false;

  /// Spawns the process with [spawn] and starts following it.
  Future<void> begin(Future<DaemonProcess> Function() spawn) async {
    final DaemonProcess process;
    try {
      process = await spawn();
    } on Object catch (error, stackTrace) {
      l.w('AppRunRepository | cannot start flutter run: $error', stackTrace);
      if (_stopping) {
        _finish(const RunStopped());
      } else {
        _fail(RunError(title: 'Build failed', message: '$error'));
      }
      return;
    }
    final connection = _connection = DaemonConnection(process);
    // Right away: the connection drops what nobody listens to.
    _subscriptions
      ..add(connection.events.listen(_onEvent))
      ..add(connection.output.listen((line) => _add(line.text, isError: line.isError)));
    unawaited(connection.done.then(_onExit, onError: (Object _) => _onExit(-1)));
    if (_stopping) _shutDownQuietly();
  }

  /// Stops the app and completes once the process has exited.
  Future<void> stop() {
    _stopping = true;
    if (_connection != null) _shutDownQuietly();
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

  /// Calls the service extension [method] of the app with [params] and returns the answer (the
  /// extension's JSON map). Throws when the daemon cannot answer.
  Future<Map<String, Object?>> _extension(String method, Map<String, String> params) async {
    final connection = _connection;
    final appId = _appId;
    if (connection == null || appId == null) {
      throw const DaemonClosedException(method: 'app.callServiceExtension');
    }
    final answer = await connection
        .request('app.callServiceExtension', <String, Object?>{
          'appId': appId,
          'methodName': method,
          'params': params,
        })
        .timeout(_extensionTimeout);
    return answer is Map ? Map<String, Object?>.from(answer) : const <String, Object?>{};
  }

  /// How long the app may take to answer a service extension.
  static const Duration _extensionTimeout = Duration(seconds: 30);

  /// The inspector's object group of this app's screenshots.
  static const String _inspectorGroup = 'flutter_code_agent';

  /// A PNG of the running app, rendered by the widget inspector. Throws when the app cannot.
  Future<List<int>> screenshot() async {
    try {
      final root = await _extension('ext.flutter.inspector.getRootWidget', <String, String>{
        'objectGroup': _inspectorGroup,
      });
      final id = switch (root['result']) {
        {'valueId': final String valueId} => valueId,
        _ => null,
      };
      if (id == null) throw StateError('The app returned no root widget.');
      final shot = await _extension('ext.flutter.inspector.screenshot', <String, String>{
        'id': id,
        'width': '1600',
        'height': '1600',
        'maxPixelRatio': '2',
      });
      final data = shot['result'];
      if (data is! String || data.isEmpty) {
        throw StateError('The app could not render a screenshot.');
      }
      return base64Decode(data);
    } finally {
      try {
        await _extension('ext.flutter.inspector.disposeGroup', <String, String>{
          'objectGroup': _inspectorGroup,
        });
      } on Object catch (error) {
        l.v('AppRunRepository | cannot dispose the inspector group: $error');
      }
    }
  }

  /// A hot reload or restart that took [took] has finished.
  void reloaded(Duration took) {
    final running = _running;
    if (running == null || _stopping) return;
    _setRunning(running.withReload(took));
  }

  /// [_shutDown] in the background: a group that cannot be signalled is logged, never thrown into
  /// the zone. Should the process then never report its exit, the launch ends all the same.
  void _shutDownQuietly() {
    _shutDown().catchError((Object error, StackTrace stackTrace) {
      l.w('AppRunRepository | cannot stop the flutter run process group: $error', stackTrace);
      if (!_finished.isCompleted) _onExit(-1);
    }).ignore();
  }

  /// Asks the app to stop (unless it already has or the process is gone), gives it [stopTimeout]
  /// to exit, then ends the process group. Once the process has exited this only ends the group:
  /// what it left behind (the app binary, `iproxy`, log readers) is still a member.
  Future<void> _shutDown() => _shuttingDown ??= () async {
    final connection = _connection!;
    final askApp = _appId != null && !_appStopped && !_exited;
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
        _listenForErrors();
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
        if (_connection != null) _shutDownQuietly();
    }
  }

  /// Connects to the VM service of a debug app for its Flutter errors; the inspector that reports
  /// them exists only in debug. A connect that fails is logged, and the output text is parsed as
  /// before.
  void _listenForErrors() {
    final uri = _vmServiceUri;
    if (mode != BuildMode.debug || uri == null || _errorListenerTried || _stopping) return;
    _errorListenerTried = true;
    connectErrors(uri)
        .then(
          (listener) {
            if (_stopping || _finished.isCompleted) {
              _closeErrorListener(listener).ignore();
              return;
            }
            _errorListener = listener;
            parser.structuredErrors = true;
            _subscriptions.add(
              listener.errors().listen(
                (error) => _emit(parser.flutterError(error)),
                onDone: () => parser.structuredErrors = false,
              ),
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            l.w(
              'AppRunRepository | runtime errors come from the output: no VM service at $uri: $error',
              stackTrace,
            );
          },
        )
        .ignore();
  }

  /// Closes [listener]; a failure is logged, never thrown.
  static Future<void> _closeErrorListener(IFlutterErrorListener listener) async {
    try {
      await listener.close();
    } on Object catch (error, stackTrace) {
      l.w('AppRunRepository | cannot close the VM service connection: $error', stackTrace);
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

  /// Feeds [text] — possibly several lines — to the parser, each cut at [kLogLineLimit].
  void _add(String text, {required bool isError}) {
    final lines = text.isEmpty ? const <String>[''] : const LineSplitter().convert(text);
    for (final line in lines) {
      parser.add(_capped(line), isError: isError).forEach(_emit);
    }
  }

  static String _capped(String line) {
    if (line.length <= kLogLineLimit) return line;
    final more = line.length - kLogLineLimit;
    return '${line.substring(0, kLogLineLimit)}… ($more more character${more == 1 ? '' : 's'})';
  }

  void _emit(ParsedLine line) {
    if (line.level == LogLevel.error) {
      _errorLines.add(line.text);
      if (_errorLines.length > _errorLineLimit) _errorLines.removeFirst();
    }
    onLog(line.level, line.text, line.error);
  }

  void _onExit(int code) {
    if (_exited) return;
    _exited = true;
    parser.flush().forEach(_emit);
    if (_stopping || (_running != null && code == 0 && _stopError == null)) {
      _finish(const RunStopped());
    } else if (_running == null && parser.firstBuildError != null) {
      // Already in the log, where it can be sent to the agent.
      _finish(RunFailed(error: parser.firstBuildError!));
    } else {
      _fail(
        RunError(title: _running == null ? 'Build failed' : 'App exited', message: _failure(code)),
      );
    }
    // An exit nobody asked for (a crash, an exit before `app.start`, a kill from outside) still
    // ends the group, so its leftovers do not outlive the run.
    if (_connection != null) _shutDownQuietly();
  }

  /// What went wrong, for a failure that is not a compile error: the `error` of `app.stop` (for a
  /// failed build only "Build process failed") and the last error lines, which say why.
  String _failure(int code) {
    final stopError = _stopError;
    final lines = <String>[
      ?stopError,
      for (final line in _errorLines)
        if (line != stopError) line,
    ];
    return lines.isEmpty ? 'flutter run exited with code $code.' : lines.join('\n');
  }

  /// Ends the launch as failed with [error], and logs it as an error line that carries it, so it
  /// can be sent to the agent (and `@error` offers it) like a compile error.
  void _fail(RunError error) {
    onLog(LogLevel.error, '${error.title}: ${error.message}', error);
    _finish(RunFailed(error: error));
  }

  void _finish(RunState state) {
    if (_finished.isCompleted) return;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    final listener = _errorListener;
    _errorListener = null;
    onState(state);
    onDone();
    // A stop, a restart of the launch and dispose wait until the VM service connection is closed.
    _finished.complete(listener == null ? null : _closeErrorListener(listener));
  }
}
