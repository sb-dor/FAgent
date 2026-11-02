import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/daemon_process.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_template.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_code_agent/src/feature/project_opening/data/project_opening_repository.dart';
import 'package:flutter_code_agent/src/feature/project_trust/data/project_trust_repository.dart';
import 'package:l/l.dart';
import 'package:path/path.dart' as p;

/// How many lines of output a step keeps (the last ones); the progress screen shows a few of them.
const int kCreationOutputKept = 200;

/// How long to wait for the rest of a command's output once it has exited. A process it left
/// behind may hold the pipes open.
const Duration _drainTimeout = Duration(seconds: 2);

/// The last line of a step that [ProjectCreationRepositoryImpl.stop] cut off.
const String _stoppedLine = 'Stopped';

/// Runs `flutter create`, `git` and `flutter pub` for a new project and writes the architecture
/// skeleton itself, one command at a time, each in its own process group.
final class ProjectCreationRepositoryImpl implements IProjectCreationRepository {
  /// Creates the repository. [loadAsset] reads a file of the app's assets (`rootBundle.loadString`
  /// in the app); [startProcess] starts the commands; [home] defaults to `$HOME`.
  ProjectCreationRepositoryImpl({
    required this._database,
    required this._flutterSdk,
    required this._environment,
    required this._projectOpening,
    required this._projectTrust,
    required this._loadAsset,
    this._startProcess = startGroupedDaemonProcess,
    String? home,
  }) : _home = home ?? Platform.environment['HOME'] ?? p.separator;

  final AppDatabase _database;
  final IFlutterSdkRepository _flutterSdk;
  final ShellEnvironment _environment;
  final IProjectOpeningRepository _projectOpening;
  final IProjectTrustRepository _projectTrust;
  final Future<String> Function(String key) _loadAsset;
  final DaemonProcessStarter _startProcess;
  final String _home;

  /// The creations being listened to.
  final Set<_Run> _runs = <_Run>{};

  @override
  Future<String> defaultParent() async {
    try {
      final last =
          await (_database.select(_database.projectsTable)
                ..where((t) => t.lastOpenedAt.isNotNull())
                ..orderBy([(t) => OrderingTerm.desc(t.lastOpenedAt)])
                ..limit(1))
              .getSingleOrNull();
      if (last != null) {
        final parent = p.dirname(last.path);
        if (Directory(parent).existsSync()) return parent;
      }
      final studio = p.join(_home, 'StudioProjects');
      return Directory(studio).existsSync() ? studio : _home;
    } on Object catch (error, stackTrace) {
      l.w('Project creation | default folder | falling back to home: $error', stackTrace);
      return _home;
    }
  }

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async {
    if (!Directory(parent).existsSync()) return TargetProblem.parentMissing;
    final type = FileSystemEntity.typeSync(p.join(parent, name), followLinks: false);
    return type == FileSystemEntityType.notFound ? null : TargetProblem.exists;
  }

  @override
  Stream<CreationRun> create(NewProjectRequest request) {
    final controller = StreamController<CreationRun>();
    final run = _Run(request, controller);
    controller
      ..onListen = () {
        _runs.add(run);
        Future<void>(() async {
          try {
            await _execute(run);
          } on Object catch (error, stackTrace) {
            if (!run.cancelled && !controller.isClosed) controller.addError(error, stackTrace);
          } finally {
            _runs.remove(run);
            if (!controller.isClosed) controller.close().ignore();
          }
        }).ignore();
      }
      ..onCancel = () => _cancel(run);
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    for (final run in _runs.toList()) {
      run.stopped = true;
      await _stopProcess(run);
    }
  }

  @override
  Future<void> dispose() async {
    await Future.wait<void>(<Future<void>>[for (final run in _runs.toList()) _cancel(run)]);
  }

  /// Ends [run] without a word: kills its command and closes its stream.
  Future<void> _cancel(_Run run) async {
    run.cancelled = true;
    await _stopProcess(run);
    if (!run.controller.isClosed) run.controller.close().ignore();
  }

  Future<void> _stopProcess(_Run run) async {
    try {
      await run.process?.stop();
    } on Object catch (error, stackTrace) {
      l.w('Project creation | stopping the command failed: $error', stackTrace);
    }
  }

  /// Runs the steps of [run] in order, until one fails, then adds the project if `flutter create`
  /// is done.
  Future<void> _execute(_Run run) async {
    run.emit();
    for (var index = 0; index < run.steps.length; index++) {
      final kind = run.steps[index].kind;
      run.update(index, (step) => step.copyWith(status: CreationStepStatus.running));
      final stopwatch = Stopwatch()..start();
      try {
        run.checkLive();
        await _runStep(run, index);
        run.update(
          index,
          (step) => step.copyWith(status: CreationStepStatus.done, took: stopwatch.elapsed),
        );
      } on _Cancelled {
        return;
      } on Object catch (error, stackTrace) {
        if (run.cancelled) return;
        final String? line;
        if (error is _StepFailure) {
          line = error.line;
        } else {
          l.w('Project creation | ${kind.name} failed: $error', stackTrace);
          line = '$error';
        }
        run.update(
          index,
          (step) => step.copyWith(
            status: CreationStepStatus.failed,
            output: line == null ? step.output : _bounded(<String>[...step.output, line]),
          ),
        );
        break;
      }
    }
    if (run.cancelled || run.steps.first.status != CreationStepStatus.done) return;
    final project = await _projectOpening.open(run.request.path);
    if (run.cancelled) return;
    await _projectTrust.trust(project.id);
    run.emit(projectId: project.id);
  }

  Future<void> _runStep(_Run run, int index) async {
    final request = run.request;
    final path = request.path;
    switch (run.steps[index].kind) {
      case CreationStepKind.flutterCreate:
        // `flutter create` writes into an existing folder without a word.
        final problem = await checkTarget(request.parent, request.name);
        if (problem != null) {
          throw _StepFailure(switch (problem) {
            TargetProblem.exists => 'The folder already exists',
            TargetProblem.parentMissing => 'The folder does not exist',
          });
        }
        final platforms = FlutterPlatform.values.where(request.platforms.contains);
        await _command(run, index, await _flutter(run), <String>[
          'create',
          '--org',
          request.org,
          '--project-name',
          request.name,
          '--platforms',
          platforms.map((platform) => platform.name).join(','),
          if (request.template == NewProjectTemplate.architecture) '--no-pub',
          path,
        ], workingDirectory: request.parent);
      case CreationStepKind.gitInit:
        await _command(run, index, _git(), const <String>['init'], workingDirectory: path);
      case CreationStepKind.skeleton:
        await _writeSkeleton(run, index);
        final flutter = await _flutter(run);
        await _command(run, index, flutter, <String>[
          'pub',
          'add',
          ...skeletonPubAddArguments,
        ], workingDirectory: path);
        await _command(run, index, flutter, const <String>['pub', 'get'], workingDirectory: path);
      case CreationStepKind.analyze:
        await _command(run, index, await _flutter(run), const <String>[
          'analyze',
        ], workingDirectory: path);
      case CreationStepKind.firstCommit:
        final git = _git();
        await _command(run, index, git, const <String>['add', '-A'], workingDirectory: path);
        await _command(run, index, git, const <String>[
          'commit',
          '-m',
          'Initial commit',
        ], workingDirectory: path);
    }
  }

  /// The `flutter` of the SDK the form shows, looked up once per creation.
  Future<String> _flutter(_Run run) async => run.flutter ??=
      (await _flutterSdk.pathFor(null)) ?? (throw const _StepFailure('Flutter SDK not found'));

  String _git() => _environment.which('git') ?? (throw const _StepFailure('git not found'));

  /// Copies the template with the package name filled in, then turns gen-l10n on in
  /// `pubspec.yaml`.
  Future<void> _writeSkeleton(_Run run, int index) async {
    final path = run.request.path;
    for (final relative in projectTemplateFiles) {
      final text = await _loadAsset('$projectTemplateRoot$relative');
      final file = File(p.joinAll(<String>[path, ...relative.split('/')]));
      await file.parent.create(recursive: true);
      await file.writeAsString(fillProjectTemplate(text, package: run.request.name));
      run
        ..addLine(index, '✎ $relative')
        ..checkLive();
    }
    final pubspec = File(p.join(path, 'pubspec.yaml'));
    final lines = (await pubspec.readAsString()).split('\n');
    final flutter = lines.indexOf('flutter:');
    if (flutter < 0) throw const _StepFailure('pubspec.yaml has no flutter: section');
    lines.insert(flutter + 1, '  generate: true');
    await pubspec.writeAsString(lines.join('\n'));
  }

  /// Runs [executable] in [workingDirectory] with the shell environment, its stdout and stderr
  /// going into the output of step [index]. Throws [_StepFailure] on a non-zero exit code.
  Future<void> _command(
    _Run run,
    int index,
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    run.checkLive();
    final process = await _startProcess(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: _environment.variables,
    );
    run.process = process;
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    final subscriptions = <StreamSubscription<String>>[
      process.stdoutLines.listen(
        (line) => run.addLine(index, line),
        onError: (Object _) {},
        onDone: stdoutDone.complete,
      ),
      process.stderrLines.listen(
        (line) => run.addLine(index, line),
        onError: (Object _) {},
        onDone: stderrDone.complete,
      ),
    ];
    try {
      // Stopped while it was starting.
      if (run.stopped || run.cancelled) await _stopProcess(run);
      final exitCode = await process.exitCode;
      await Future.wait<void>(<Future<void>>[stdoutDone.future, stderrDone.future])
          .timeout(_drainTimeout, onTimeout: () => const <void>[]);
      run.checkLive();
      if (exitCode != 0) throw const _StepFailure(null);
    } finally {
      run.process = null;
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }
}

/// The last [kCreationOutputKept] of [lines].
List<String> _bounded(List<String> lines) =>
    lines.length <= kCreationOutputKept ? lines : lines.sublist(lines.length - kCreationOutputKept);

/// One creation: its steps as of now and the command running for it.
final class _Run {
  _Run(this.request, this.controller)
    : steps = <CreationStep>[
        for (final kind in creationStepsFor(request)) CreationStep(kind: kind),
      ];

  final NewProjectRequest request;
  final StreamController<CreationRun> controller;
  List<CreationStep> steps;

  /// The command running now.
  DaemonProcess? process;

  /// The `flutter` executable, once looked up.
  String? flutter;

  /// [ProjectCreationRepositoryImpl.stop] was called: the step fails, nothing further runs.
  bool stopped = false;

  /// The subscription was cancelled or the repository disposed: nothing more is emitted.
  bool cancelled = false;

  /// Throws when the run must not go on.
  void checkLive() {
    if (cancelled) throw const _Cancelled();
    if (stopped) throw const _StepFailure(_stoppedLine);
  }

  void emit({int? projectId}) {
    if (cancelled || controller.isClosed) return;
    controller.add(CreationRun(steps: steps, projectId: projectId));
  }

  void update(int index, CreationStep Function(CreationStep step) change) {
    steps = List<CreationStep>.of(steps)..[index] = change(steps[index]);
    emit();
  }

  void addLine(int index, String line) =>
      update(index, (step) => step.copyWith(output: _bounded(<String>[...step.output, line])));
}

/// A step failed; [line] (if any) ends its output.
final class _StepFailure implements Exception {
  const _StepFailure(this.line);

  final String? line;

  @override
  String toString() => 'Step failed: $line';
}

/// The run was cancelled; it ends without a word.
final class _Cancelled implements Exception {
  const _Cancelled();
}
