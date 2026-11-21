import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/daemon_process.dart';
import 'package:flutter_code_agent/src/common/pub_workspace/pub_workspace.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_template.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_member_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:l/l.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// How many lines of output a step keeps (the last ones); the progress screen shows a few of them.
const int kCreationOutputKept = 200;

/// How long to wait for the rest of a command's output once it has exited. A process it left
/// behind may hold the pipes open.
const Duration _drainTimeout = Duration(seconds: 2);

/// The last line of a step that [ProjectCreationRepositoryImpl.stop] cut off.
const String _stoppedLine = 'Stopped';

/// How long cancelling an add waits for it to roll back; a command that will not die may hold it.
const Duration _rollbackWait = Duration(seconds: 5);

/// Runs `flutter create`, `git` and `flutter pub` for a new project, or for a member added to a
/// monorepo, and writes the architecture skeleton itself, one command at a time, each in its own
/// process group.
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
  Stream<CreationRun> create(NewProjectRequest request) => _start(_Run.project(request));

  @override
  Stream<CreationRun> addMember(NewMemberRequest request) => _start(_Run.member(request));

  @override
  Future<MemberProblem?> checkMember(
    String projectPath,
    MemberKind kind,
    String folder,
    String packageName,
  ) async {
    final type = FileSystemEntity.typeSync(
      p.join(projectPath, kind.parent, folder),
      followLinks: false,
    );
    if (type != FileSystemEntityType.notFound) return MemberProblem.folderExists;
    final taken = <String?>{
      workspacePackageName(projectPath),
      for (final member in workspaceMembers(projectPath)) member.packageName,
    };
    return taken.contains(packageName) ? MemberProblem.packageTaken : null;
  }

  @override
  Future<String> suggestedPackageName(String projectPath, String folder) async {
    const suffix = '_workspace';
    final name = workspacePackageName(projectPath);
    final project = name != null && name.endsWith(suffix) && name.length > suffix.length
        ? name.substring(0, name.length - suffix.length)
        : p.basename(projectPath);
    return '${project}_$folder';
  }

  @override
  Future<bool> hasUiPackage(String projectPath) async =>
      File(p.join(projectPath, 'packages', 'ui', 'pubspec.yaml')).existsSync();

  @override
  Future<bool> isGitRepo(String projectPath) async =>
      // A worktree has a `.git` file instead of a folder.
      FileSystemEntity.typeSync(p.join(projectPath, '.git')) != FileSystemEntityType.notFound;

  @override
  Future<List<String>> scriptsListingMembers(String projectPath) async {
    final scripts = Directory(p.join(projectPath, 'scripts'));
    if (!scripts.existsSync()) return const <String>[];
    final names = <RegExp>[
      for (final member in workspaceMembers(projectPath))
        // `packages/core`, not `packages/core_utils` or `mypackages/core`.
        RegExp('(?<![\\w-])${RegExp.escape(member.folder)}(?![\\w-])'),
    ];
    if (names.isEmpty) return const <String>[];
    final listing = <String>[];
    try {
      await for (final entity in scripts.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final String text;
        try {
          text = await entity.readAsString();
        } on FileSystemException {
          continue; // Not text.
        }
        if (names.any((name) => name.hasMatch(text))) {
          listing.add(p.split(p.relative(entity.path, from: projectPath)).join('/'));
        }
      }
    } on FileSystemException catch (error, stackTrace) {
      l.w('Project creation | reading scripts failed: $error', stackTrace);
    }
    return listing..sort();
  }

  /// The stream of [run]: runs its steps once it is listened to.
  Stream<CreationRun> _start(_Run run) {
    final controller = run.controller;
    controller
      ..onListen = () {
        _runs.add(run);
        Future<void>(() async {
          try {
            if (run.member != null) await _saveLock(run);
            await _execute(run);
          } on Object catch (error, stackTrace) {
            if (!run.cancelled && !controller.isClosed) controller.addError(error, stackTrace);
          } finally {
            if (run.member case final member? when run.created && !run.kept) {
              await _rollBack(run, member);
            }
            _runs.remove(run);
            if (!controller.isClosed) controller.close().ignore();
            run.finished.complete();
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

  /// Ends [run] without a word: kills its command and closes its stream. An add waits until it
  /// has rolled back.
  Future<void> _cancel(_Run run) async {
    run.cancelled = true;
    await _stopProcess(run);
    if (!run.controller.isClosed) run.controller.close().ignore();
    if (run.member != null) {
      await run.finished.future.timeout(
        _rollbackWait,
        onTimeout: () {
          l.w('Project creation | the add did not end in time to roll back');
        },
      );
    }
  }

  /// Keeps the root's `pubspec.lock` of an add (or that there is none), for [_rollBack].
  Future<void> _saveLock(_Run run) async {
    final lock = File(p.join(run.root, 'pubspec.lock'));
    run.savedLock = lock.existsSync() ? await lock.readAsBytes() : null;
  }

  /// Undoes an add that did not get to its commit: unstages what it staged, deletes the member's
  /// folder and puts the root's `pubspec.lock` back. Touches nothing else. Never throws.
  Future<void> _rollBack(_Run run, NewMemberRequest member) async {
    if (run.staged case final paths?) await _unstage(member, paths);
    String line;
    try {
      final folder = Directory(member.path);
      if (folder.existsSync()) await folder.delete(recursive: true);
      final lock = File(p.join(member.projectPath, 'pubspec.lock'));
      if (run.savedLock case final bytes?) {
        await lock.writeAsBytes(bytes, flush: true);
      } else if (lock.existsSync()) {
        await lock.delete();
      }
      line = 'Removed ${member.relative}';
    } on Object catch (error, stackTrace) {
      l.w('Project creation | rolling back ${member.relative} failed: $error', stackTrace);
      line = 'Could not remove ${member.relative}: $error';
    }
    final last = run.steps.lastIndexWhere((step) => step.status != CreationStepStatus.pending);
    if (last >= 0) run.addLine(last, line);
  }

  /// `git reset -q -- <paths>`: takes the [paths] the add staged out of the index again. Runs
  /// while the run is stopped or cancelled, so outside [_command]; its output is dropped. Never
  /// throws.
  Future<void> _unstage(NewMemberRequest member, List<String> paths) async {
    try {
      final process = await _startProcess(
        _git(),
        <String>['reset', '-q', '--', ...paths],
        workingDirectory: member.projectPath,
        environment: _environment.variables,
      );
      final subscriptions = <StreamSubscription<String>>[
        process.stdoutLines.listen(null, onError: (Object _) {}),
        process.stderrLines.listen(null, onError: (Object _) {}),
      ];
      try {
        final exitCode = await process.exitCode.timeout(_rollbackWait);
        if (exitCode != 0) {
          l.w('Project creation | git reset of ${member.relative} exited $exitCode');
        }
      } on TimeoutException {
        await process.stop();
        l.w('Project creation | git reset of ${member.relative} did not end in time; killed it');
      } finally {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      }
    } on Object catch (error, stackTrace) {
      l.w('Project creation | unstaging ${member.relative} failed: $error', stackTrace);
    }
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
    final root = run.root;
    final member = run.member;
    switch (run.steps[index].kind) {
      case CreationStepKind.workspace:
        await _writeWorkspace(run, index);
      case CreationStepKind.memberCreate:
        await _createAddedMember(run, index, member!);
      case CreationStepKind.pubGet:
        await _command(run, index, await _flutter(run), const <String>[
          'pub',
          'get',
        ], workingDirectory: root);
      case CreationStepKind.commit:
        // Only what the add made: with the pathspec, what the user had staged stays staged and out
        // of the commit.
        final git = _git();
        // A repository that ignores the lock (and does not track it) fails `git add` and the
        // commit's pathspec on it: then only the member goes in. A tracked lock is never ignored.
        final lockIgnored =
            await _command(
              run,
              index,
              git,
              const <String>['check-ignore', '-q', 'pubspec.lock'],
              workingDirectory: root,
              accepted: const <int>{0, 1},
            ) ==
            0;
        final paths = <String>[member!.relative, if (!lockIgnored) 'pubspec.lock'];
        run.staged = paths;
        await _command(run, index, git, <String>['add', ...paths], workingDirectory: root);
        await _command(
          run,
          index,
          git,
          <String>[
            'commit',
            '-m',
            'Add ${member.kind.commitLabel} ${member.folder}',
            '--',
            ...paths,
          ],
          workingDirectory: root,
          // Committed is committed, even when a stop lands before the step is marked done.
          succeeded: () => run.committed = true,
        );
      case CreationStepKind.flutterCreate:
        final request = run.request;
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
          root,
        ], workingDirectory: request.parent);
      case CreationStepKind.gitInit:
        await _command(run, index, _git(), const <String>['init'], workingDirectory: root);
      case CreationStepKind.skeleton:
        if (member != null) {
          await _writeAppSkeleton(
            run,
            index,
            appPath: member.path,
            package: member.packageName,
            monorepo: true,
          );
          // A root without `build_runner` cannot build the workspace; the member has it.
          final atRoot = _dependsOn(_rootPubspec(root), 'build_runner');
          await _installSkeleton(
            run,
            index,
            appPath: member.path,
            buildIn: atRoot ? root : member.path,
            workspace: atRoot,
            // Only the member's files: the rest of the repository is the user's.
            fixIn: member.path,
          );
          return;
        }
        final request = run.request;
        final monorepo = request.monorepo;
        if (monorepo) await _writeUiPackage(run, index, root);
        await _writeAppSkeleton(
          run,
          index,
          appPath: request.appPath,
          package: monorepo ? request.appPackageName : request.name,
          monorepo: monorepo,
        );
        await _installSkeleton(
          run,
          index,
          appPath: request.appPath,
          // The root has no dependencies yet; `build_runner build --workspace` runs from it.
          addRootBuildRunner: monorepo,
          buildIn: root,
          workspace: monorepo,
          fixIn: root,
        );
      case CreationStepKind.analyze:
        // An added member is checked alone; a new project as a whole.
        await _command(run, index, await _flutter(run), const <String>[
          'analyze',
        ], workingDirectory: member?.path ?? root);
      case CreationStepKind.rules:
        for (final name in await _writeRules(root)) {
          run.addLine(index, '✎ docs/rules/$name.md');
        }
      case CreationStepKind.firstCommit:
        final git = _git();
        await _command(run, index, git, const <String>['add', '-A'], workingDirectory: root);
        await _command(run, index, git, const <String>[
          'commit',
          '-m',
          'Initial commit',
        ], workingDirectory: root);
    }
  }

  /// The packages of the skeleton and their generated code: `pub add` in [appPath], `pub get` at
  /// the root, `build_runner` in [buildIn] (over the whole [workspace] or that package alone), and
  /// the imports sorted in [fixIn]. With [addRootBuildRunner] the root gets `build_runner` first.
  Future<void> _installSkeleton(
    _Run run,
    int index, {
    required String appPath,
    required String buildIn,
    required bool workspace,
    required String fixIn,
    bool addRootBuildRunner = false,
  }) async {
    final root = run.root;
    final flutter = await _flutter(run);
    await _command(run, index, flutter, <String>[
      'pub',
      'add',
      ...skeletonPubAddArgumentsFor(
        uiPath: appPath == root ? 'packages/ui' : p.join('..', '..', 'packages', 'ui'),
      ),
    ], workingDirectory: appPath);
    if (addRootBuildRunner) {
      await _command(run, index, flutter, const <String>[
        'pub',
        'add',
        'dev:build_runner',
      ], workingDirectory: root);
    }
    await _command(run, index, flutter, const <String>['pub', 'get'], workingDirectory: root);
    // The drift database (`lib/_core/database/`) needs its generated part to compile.
    await _command(run, index, _dart(flutter), <String>[
      'run',
      'build_runner',
      'build',
      if (workspace) '--workspace',
      '--delete-conflicting-outputs',
    ], workingDirectory: buildIn);
    // The template's imports are sorted for no package in particular; `directives_ordering`
    // (analysis_options.yaml) wants them sorted for this one.
    await _command(run, index, _dart(flutter), const <String>[
      'fix',
      '--apply',
      '--code=directives_ordering',
    ], workingDirectory: fixIn);
  }

  /// The `memberCreate` step of an add: checks that the folder is free, then creates the member
  /// with the SDK constraint of the root's `pubspec.yaml`.
  Future<void> _createAddedMember(_Run run, int index, NewMemberRequest member) async {
    // `flutter create` writes into an existing folder without a word.
    final type = FileSystemEntity.typeSync(member.path, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      throw const _StepFailure('The folder already exists');
    }
    final environment = _rootPubspec(member.projectPath)?['environment'];
    final constraint = environment is YamlMap ? environment['sdk'] : null;
    if (constraint is! String) {
      throw const _StepFailure('The root pubspec.yaml has no environment: sdk:');
    }
    // From here on the folder is the add's own, and a rollback may delete it.
    run.created = true;
    await _createMember(
      run,
      index,
      kind: member.kind,
      path: member.path,
      packageName: member.packageName,
      org: member.org,
      platforms: member.platforms,
      sdkConstraint: constraint,
    );
  }

  /// The root `pubspec.yaml` of the project at [root]; `null` when it is missing or unreadable.
  YamlMap? _rootPubspec(String root) {
    try {
      final yaml = loadYaml(File(p.join(root, 'pubspec.yaml')).readAsStringSync());
      return yaml is YamlMap ? yaml : null;
    } on Object catch (error, stackTrace) {
      l.w('Project creation | reading $root/pubspec.yaml failed: $error', stackTrace);
      return null;
    }
  }

  /// Whether [pubspec] lists [package] in its dependencies or dev dependencies.
  bool _dependsOn(YamlMap? pubspec, String package) => <Object?>[
    pubspec?['dependencies'],
    pubspec?['dev_dependencies'],
  ].any((section) => section is YamlMap && section.containsKey(package));

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

  /// Writes `packages/ui` of a monorepo at [root]. Its template pubspec already has
  /// `resolution: workspace`, and it keeps its own SDK constraint: on the root's (3.14 and newer)
  /// its private fields trip `prefer_initializing_formals`.
  Future<void> _writeUiPackage(_Run run, int index, String root) => _copyTemplate(
    run,
    index,
    assetRoot: projectTemplateRoot,
    files: projectTemplateUiFiles,
    to: root,
    package: run.request.name,
  );

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
    final created = await _joinWorkspace(
      File(p.join(path, 'pubspec.yaml')),
      sdkConstraint,
      name: packageName,
    );
    // `dart create` names the package after the folder; its `bin/` and `test/` import it.
    if (created != null && created != packageName)
      await _renameImports(Directory(path), created, packageName);
    if (kind == MemberKind.dartApp || kind == MemberKind.dartPackage)
      await _printToStdout(Directory(path));
    // The member's own `analysis_options.yaml` would shadow the root's; it inherits it instead.
    await File(p.join(path, 'analysis_options.yaml'))
        .writeAsString('include: ../../analysis_options.yaml\n');
  }

  /// Makes the samples `dart create` writes into `bin/` and `example/` of [directory] call
  /// `stdout.writeln` instead of `print`, which the root's `avoid_print` reports.
  Future<void> _printToStdout(Directory directory) async {
    final call = RegExp(r'\bprint\(');
    for (final folder in const <String>['bin', 'example']) {
      final samples = Directory(p.join(directory.path, folder));
      if (!samples.existsSync()) continue;
      await for (final entity in samples.list(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = await entity.readAsString();
        if (!call.hasMatch(text)) continue;
        final io = text.contains("import 'dart:io';") ? '' : "import 'dart:io';\n\n";
        await entity.writeAsString('$io${text.replaceAll(call, 'stdout.writeln(')}');
      }
    }
  }

  /// Replaces `package:[from]/` with `package:[to]/` in the Dart files under [directory].
  Future<void> _renameImports(Directory directory, String from, String to) async {
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = p.split(p.relative(entity.path, from: directory.path));
      if (relative.contains('.dart_tool') || relative.contains('build')) continue;
      final text = await entity.readAsString();
      if (text.contains('package:$from/')) {
        await entity.writeAsString(text.replaceAll('package:$from/', 'package:$to/'));
      }
    }
  }

  /// Edits the `pubspec.yaml` of a member: [name] (when given), the SDK constraint of the root and
  /// `resolution: workspace` after the `environment:` block. Returns the name the package had.
  Future<String?> _joinWorkspace(File pubspec, String sdkConstraint, {String? name}) async {
    final lines = (await pubspec.readAsString()).split('\n');
    String? was;
    if (name != null) {
      final at = lines.indexWhere((line) => line.startsWith('name:'));
      if (at < 0) throw const _StepFailure('pubspec.yaml has no name:');
      was = lines[at].substring('name:'.length).trim();
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
    return was;
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
      label: monorepo ? '${p.split(p.relative(appPath, from: run.root)).join('/')}/' : '',
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
  /// going into the output of step [index]. Returns its exit code; throws [_StepFailure] on one
  /// that is not [accepted]. [succeeded] is called as soon as it exits with 0, before a stop or
  /// cancel can fail the step.
  Future<int> _command(
    _Run run,
    int index,
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Set<int> accepted = const <int>{0},
    void Function()? succeeded,
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
      if (exitCode == 0) succeeded?.call();
      await Future.wait<void>(<Future<void>>[stdoutDone.future, stderrDone.future])
          .timeout(_drainTimeout, onTimeout: () => const <void>[]);
      run.checkLive();
      if (!accepted.contains(exitCode)) throw const _StepFailure(null);
      return exitCode;
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

/// One creation, of a project or of a member added to a monorepo: its steps as of now and the
/// command running for it.
final class _Run {
  _Run.project(NewProjectRequest this.project)
    : member = null,
      root = project.path,
      steps = <CreationStep>[
        for (final kind in creationStepsFor(project)) CreationStep(kind: kind),
      ];

  _Run.member(NewMemberRequest this.member)
    : project = null,
      root = member.projectPath,
      steps = <CreationStep>[for (final kind in memberStepsFor(member)) CreationStep(kind: kind)];

  /// The new project; `null` for an add.
  final NewProjectRequest? project;

  /// The member to add; `null` for a new project.
  final NewMemberRequest? member;

  /// The project folder: the new one, or the monorepo the member is added to.
  final String root;

  final StreamController<CreationRun> controller = StreamController<CreationRun>();
  List<CreationStep> steps;

  /// Completes once the run is over, an add rolled back included.
  final Completer<void> finished = Completer<void>();

  /// The command running now.
  DaemonProcess? process;

  /// The `flutter` executable, once looked up.
  String? flutter;

  /// The SDK constraint of a monorepo, once the workspace step worked it out.
  String? sdkConstraint;

  /// The root's `pubspec.lock` before an add; `null` when there was none.
  Uint8List? savedLock;

  /// An add got past its folder check: the member's folder is its own to delete.
  bool created = false;

  /// The paths an add gave to `git add`: a rollback takes them out of the index again.
  List<String>? staged;

  /// An add's `git commit` exited with 0: it is never rolled back.
  bool committed = false;

  /// [ProjectCreationRepositoryImpl.stop] was called: the step fails, nothing further runs.
  bool stopped = false;

  /// The subscription was cancelled or the repository disposed: nothing more is emitted.
  bool cancelled = false;

  /// The new project; only the steps of a new project ask for it.
  NewProjectRequest get request => project ?? (throw StateError('Not a new project'));

  /// Whether an add is past undoing: its commit went through, or every step but `analyze` is
  /// done. The commit (or, without one, the step before `analyze`) is the last one a rollback
  /// covers.
  bool get kept =>
      committed ||
      steps.every(
        (step) => step.kind == CreationStepKind.analyze || step.status == CreationStepStatus.done,
      );

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
