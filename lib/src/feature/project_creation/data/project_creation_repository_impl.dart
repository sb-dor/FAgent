import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/daemon_process.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_template.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_member_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
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
  /// Creates the repository. [flutter] gives the `flutter` executable of the SDK the form shows
  /// (`null` when there is none); [writeRules] writes the enabled built-in rules into a project
  /// folder and returns their names; [loadAsset] reads a file of the app's assets
  /// (`rootBundle.loadString` in the app); [startProcess] starts the commands; [home] defaults to
  /// `$HOME`; [now] gives the date of the first `CHANGELOG.md` entry; [dartVersion] gives the Dart
  /// version of that SDK (for example `3.14.0`), which a monorepo needs for its SDK constraint.
  ProjectCreationRepositoryImpl({
    required this._database,
    required Future<String?> Function() flutter,
    required this._environment,
    required this._writeRules,
    required this._loadAsset,
    this._startProcess = startGroupedDaemonProcess,
    this._now = DateTime.now,
    Future<String?> Function()? dartVersion,
    String? home,
  }) : _flutterPath = flutter,
       _dartVersion = dartVersion ?? (() async => null),
       _home = home ?? Platform.environment['HOME'] ?? p.separator;

  final AppDatabase _database;
  final Future<String?> Function() _flutterPath;
  final Future<String?> Function() _dartVersion;
  final ShellEnvironment _environment;
  final Future<List<String>> Function(String projectPath) _writeRules;
  final Future<String> Function(String key) _loadAsset;
  final DaemonProcessStarter _startProcess;
  final DateTime Function() _now;
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

  /// Runs the steps of [run] in order, until one fails.
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
  }

  Future<void> _runStep(_Run run, int index) async {
    final request = run.request;
    final path = request.path;
    switch (run.steps[index].kind) {
      case CreationStepKind.workspace:
        await _writeWorkspace(run, index);
      case CreationStepKind.pubGet:
        await _command(run, index, await _flutter(run), const <String>[
          'pub',
          'get',
        ], workingDirectory: path);
      case CreationStepKind.memberCreate:
      case CreationStepKind.commit:
        throw UnimplementedError('${run.steps[index].kind.name}: Task 5');
      case CreationStepKind.flutterCreate:
        if (request.monorepo) {
          // The workspace step checked the folder of the project.
          await _createMember(
            run,
            index,
            kind: MemberKind.flutterApp,
            path: request.appPath,
            packageName: request.appPackageName,
            org: request.org,
            platforms: request.platforms,
            sdkConstraint: _sdkConstraint(run),
          );
          return;
        }
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
          '--template',
          request.type.template,
          '--org',
          request.org,
          '--project-name',
          request.name,
          // `flutter create` takes platforms only for an app and a plugin.
          if (request.type.hasPlatforms) ...<String>[
            '--platforms',
            platforms.map((platform) => platform.name).join(','),
          ],
          // The skeleton step adds the packages first, then runs `pub get` itself.
          if (request.skeleton) '--no-pub',
          path,
        ], workingDirectory: request.parent);
      case CreationStepKind.gitInit:
        await _command(run, index, _git(), const <String>['init'], workingDirectory: path);
      case CreationStepKind.skeleton:
        final monorepo = request.monorepo;
        if (monorepo) await _writeUiPackage(run, index, request.path, _sdkConstraint(run));
        await _writeAppSkeleton(
          run,
          index,
          appPath: request.appPath,
          package: monorepo ? request.appPackageName : request.name,
          monorepo: monorepo,
        );
        final flutter = await _flutter(run);
        await _command(run, index, flutter, <String>[
          'pub',
          'add',
          ...skeletonPubAddArgumentsFor(
            uiPath: monorepo ? p.join('..', '..', 'packages', 'ui') : 'packages/ui',
          ),
        ], workingDirectory: request.appPath);
        if (monorepo) {
          // The root has no dependencies yet; `build_runner build --workspace` runs from it.
          await _command(run, index, flutter, const <String>[
            'pub',
            'add',
            'dev:build_runner',
          ], workingDirectory: path);
        }
        await _command(run, index, flutter, const <String>['pub', 'get'], workingDirectory: path);
        // The drift database (`lib/_core/database/`) needs its generated part to compile.
        await _command(run, index, _dart(flutter), <String>[
          'run',
          'build_runner',
          'build',
          if (monorepo) '--workspace',
          '--delete-conflicting-outputs',
        ], workingDirectory: path);
        // The template's imports are sorted for no package in particular; `directives_ordering`
        // (analysis_options.yaml) wants them sorted for this one.
        await _command(run, index, _dart(flutter), const <String>[
          'fix',
          '--apply',
          '--code=directives_ordering',
        ], workingDirectory: path);
      case CreationStepKind.analyze:
        await _command(run, index, await _flutter(run), const <String>[
          'analyze',
        ], workingDirectory: path);
      case CreationStepKind.rules:
        for (final name in await _writeRules(path)) {
          run.addLine(index, '✎ docs/rules/$name.md');
        }
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
  Future<String> _flutter(_Run run) async =>
      run.flutter ??= (await _flutterPath()) ?? (throw const _StepFailure('Flutter SDK not found'));

  /// The `dart` next to [flutter] in the SDK's `bin` folder.
  String _dart(String flutter) =>
      p.join(p.dirname(flutter), Platform.isWindows ? 'dart.bat' : 'dart');

  String _git() => _environment.which('git') ?? (throw const _StepFailure('git not found'));

  /// The SDK constraint of a monorepo (`^3.14.0`), worked out by the workspace step.
  String _sdkConstraint(_Run run) =>
      run.sdkConstraint ?? (throw const _StepFailure('Dart version unknown'));

  /// The root of a monorepo: its `pubspec.yaml`, `.gitignore`, scripts, `Makefile`,
  /// `analysis_options.yaml` and `CHANGELOG.md`. Creates the project folder.
  Future<void> _writeWorkspace(_Run run, int index) async {
    final request = run.request;
    final problem = await checkTarget(request.parent, request.name);
    if (problem != null) {
      throw _StepFailure(switch (problem) {
        TargetProblem.exists => 'The folder already exists',
        TargetProblem.parentMissing => 'The folder does not exist',
      });
    }
    final constraint = _constraintOf(await _dartVersion());
    if (constraint == null) throw const _StepFailure('Dart version unknown');
    run.sdkConstraint = constraint;
    final root = Directory(request.path);
    await root.create();
    await File(p.join(request.path, 'pubspec.yaml'))
        .writeAsString(monorepoRootPubspec(name: request.name, sdkConstraint: constraint));
    run.addLine(index, '✎ pubspec.yaml');
    await File(p.join(request.path, '.gitignore')).writeAsString(_workspaceGitignore);
    run.addLine(index, '✎ .gitignore');
    await _copyTemplate(
      run,
      index,
      assetRoot: monorepoTemplateRoot,
      files: monorepoTemplateFiles,
      to: request.path,
      package: request.name,
    );
    await _copyTemplate(
      run,
      index,
      assetRoot: projectTemplateRoot,
      files: _workspaceRepoFiles,
      to: request.path,
      package: request.name,
    );
  }

  /// Copies [files] of the assets at [assetRoot] into [to], with the package name filled in. Each
  /// copy is a line of the step's output: its path relative to [to], behind [label].
  Future<void> _copyTemplate(
    _Run run,
    int index, {
    required String assetRoot,
    required List<String> files,
    required String to,
    required String package,
    String label = '',
  }) async {
    for (final relative in files) {
      final text = await _loadAsset('$assetRoot$relative');
      final file = File(p.joinAll(<String>[to, ...relative.split('/')]));
      await file.parent.create(recursive: true);
      await file.writeAsString(fillProjectTemplate(text, package: package, date: _now()));
      run
        ..addLine(index, '✎ $label$relative')
        ..checkLive();
    }
  }

  /// Writes `packages/ui` of a monorepo at [root] and joins it to the workspace.
  Future<void> _writeUiPackage(_Run run, int index, String root, String sdkConstraint) async {
    await _copyTemplate(
      run,
      index,
      assetRoot: projectTemplateRoot,
      files: projectTemplateUiFiles,
      to: root,
      package: run.request.name,
    );
    await _joinWorkspace(File(p.join(root, 'packages', 'ui', 'pubspec.yaml')), sdkConstraint);
  }

  /// Creates a member of a monorepo at [path] (`<root>/<apps|packages>/<folder>`) and joins it
  /// to the workspace: `resolution: workspace` and the root's [sdkConstraint]. No `pub get` runs:
  /// the workspace does it once, at its root.
  Future<void> _createMember(
    _Run run,
    int index, {
    required MemberKind kind,
    required String path,
    required String packageName,
    required String org,
    required Set<FlutterPlatform> platforms,
    required String sdkConstraint,
  }) async {
    final root = p.dirname(p.dirname(path));
    final flutter = await _flutter(run);
    switch (kind) {
      case MemberKind.flutterApp || MemberKind.flutterPackage:
        await _command(run, index, flutter, <String>[
          'create',
          '--template',
          if (kind == MemberKind.flutterApp) 'app' else 'package',
          '--org',
          org,
          '--project-name',
          packageName,
          if (kind.hasPlatforms) ...<String>[
            '--platforms',
            FlutterPlatform.values
                .where(platforms.contains)
                .map((platform) => platform.name)
                .join(','),
          ],
          '--no-pub',
          path,
        ], workingDirectory: root);
      case MemberKind.dartApp || MemberKind.dartPackage:
        await _command(run, index, _dart(flutter), <String>[
          'create',
          '-t',
          if (kind == MemberKind.dartApp) 'console' else 'package',
          '--no-pub',
          path,
        ], workingDirectory: root);
    }
    await _joinWorkspace(File(p.join(path, 'pubspec.yaml')), sdkConstraint, name: packageName);
  }

  /// Edits the `pubspec.yaml` of a member: [name] (when given), the SDK constraint of the root and
  /// `resolution: workspace` after the `environment:` block.
  Future<void> _joinWorkspace(File pubspec, String sdkConstraint, {String? name}) async {
    final lines = (await pubspec.readAsString()).split('\n');
    if (name != null) {
      final at = lines.indexWhere((line) => line.startsWith('name:'));
      if (at < 0) throw const _StepFailure('pubspec.yaml has no name:');
      lines[at] = 'name: $name';
    }
    final environment = lines.indexOf('environment:');
    if (environment < 0) throw const _StepFailure('pubspec.yaml has no environment: section');
    var end = environment + 1;
    while (end < lines.length && lines[end].startsWith(' ')) {
      if (lines[end].trimLeft().startsWith('sdk:')) lines[end] = '  sdk: $sdkConstraint';
      end++;
    }
    if (!lines.contains('resolution: workspace')) {
      lines.insertAll(end, const <String>['', 'resolution: workspace']);
    }
    await pubspec.writeAsString(lines.join('\n'));
  }

  /// Copies the template with the package name filled in, then edits `pubspec.yaml`: gen-l10n on
  /// and, in a one-app project, `packages/ui` as a workspace member and the shader of its shimmer.
  /// In a [monorepo] only the app's files go to [appPath]; `packages/ui` is written apart and
  /// declares its shader itself.
  Future<void> _writeAppSkeleton(
    _Run run,
    int index, {
    required String appPath,
    required String package,
    required bool monorepo,
  }) async {
    await _copyTemplate(
      run,
      index,
      assetRoot: projectTemplateRoot,
      files: monorepo ? projectTemplateAppFiles : projectTemplateFiles,
      to: appPath,
      package: package,
      label: monorepo ? '${p.relative(appPath, from: run.request.path)}/' : '',
    );
    final pubspec = File(p.join(appPath, 'pubspec.yaml'));
    final lines = (await pubspec.readAsString()).split('\n');
    final flutter = lines.indexOf('flutter:');
    if (flutter < 0) throw const _StepFailure('pubspec.yaml has no flutter: section');
    if (monorepo) {
      lines.insertAll(flutter + 1, const <String>['  generate: true', '']);
      await pubspec.writeAsString(lines.join('\n'));
      return;
    }
    lines.insertAll(flutter + 1, const <String>[
      '  generate: true',
      '',
      '  # The shimmer of packages/ui loads it as `packages/ui/shaders/shimmer.frag`.',
      '  shaders:',
      '    - packages/ui/shaders/shimmer.frag',
    ]);
    final dependencies = lines.indexOf('dependencies:');
    if (dependencies < 0) throw const _StepFailure('pubspec.yaml has no dependencies: section');
    lines.insertAll(dependencies, const <String>[
      '# The packages of this repository: https://dart.dev/tools/pub/workspaces',
      'workspace:',
      '  - packages/ui',
      '',
    ]);
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

/// The files of the repository that a monorepo's root keeps; the rest of
/// [projectTemplateRepoFiles] (the Makefile and scripts of one app, the rename tool) is not for it.
const List<String> _workspaceRepoFiles = <String>['analysis_options.yaml', 'CHANGELOG.md'];

/// The `.gitignore` of a monorepo's root; each app and package has its own from `flutter create`.
const String _workspaceGitignore = '''
.dart_tool/
build/
.idea/
*.iml
.DS_Store
''';

/// The constraint `^<major>.<minor>.0` for [dartVersion] (`3.15.2`); `null` when it is not one.
String? _constraintOf(String? dartVersion) {
  final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(dartVersion ?? '');
  return match == null ? null : '^${match[1]}.${match[2]}.0';
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

  /// The SDK constraint of a monorepo, once the workspace step worked it out.
  String? sdkConstraint;

  /// [ProjectCreationRepositoryImpl.stop] was called: the step fails, nothing further runs.
  bool stopped = false;

  /// The subscription was cancelled or the repository disposed: nothing more is emitted.
  bool cancelled = false;

  /// Throws when the run must not go on.
  void checkLive() {
    if (cancelled) throw const _Cancelled();
    if (stopped) throw const _StepFailure(_stoppedLine);
  }

  void emit() {
    if (cancelled || controller.isClosed) return;
    controller.add(CreationRun(steps: steps));
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
