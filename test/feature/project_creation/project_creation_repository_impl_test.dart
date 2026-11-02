import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_template.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_code_agent/src/feature/project_opening/data/project_opening_repository.dart';
import 'package:flutter_code_agent/src/feature/project_trust/data/project_trust_repository.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/scripted_daemon_process.dart';

const String _flutter = '/sdk/bin/flutter';
const int _projectId = 7;

/// A `pubspec.yaml` as `flutter create` writes it, cut down.
const String _createdPubspec = '''
name: avera_booking
description: "A new Flutter project."

dependencies:
  flutter:
    sdk: flutter

# The following section is specific to Flutter packages.
flutter:

  # The following line ensures that the Material Icons font is
  # included with your application.
  uses-material-design: true
''';

final class _StubSdk implements IFlutterSdkRepository {
  String? path = _flutter;

  @override
  Future<FlutterSdk> sdkFor(String? projectPath) async => FlutterSdk(path: path);

  @override
  Future<List<DoctorCheck>> doctor() => throw UnimplementedError();
}

final class _StubOpening implements IProjectOpeningRepository {
  final List<String> opened = <String>[];
  Exception? error;

  @override
  Future<Project> open(String path) async {
    opened.add(path);
    if (error case final error?) throw error;
    return Project(id: _projectId, path: path, name: p.basename(path), isFlutter: true);
  }
}

final class _StubTrust implements IProjectTrustRepository {
  final List<int> trusted = <int>[];

  @override
  Future<List<String>> agentSettingsFiles(String projectPath) async => const <String>[];

  @override
  Future<void> trust(int projectId) async => trusted.add(projectId);
}

void main() {
  late Directory root;
  late Directory parent;
  late String bin;
  late AppDatabase database;
  late _StubSdk sdk;
  late _StubOpening opening;
  late _StubTrust trust;
  late List<ScriptedDaemonProcess> started;
  late ShellEnvironment environment;

  /// How a started process behaves; by default [_finish].
  late void Function(ScriptedDaemonProcess process) script;

  bool isCreate(ScriptedDaemonProcess process) =>
      process.executable == _flutter && process.arguments.first == 'create';

  /// Plays `flutter create` writing its `pubspec.yaml`, then prints a line and exits with 0.
  void finish(ScriptedDaemonProcess process) {
    if (isCreate(process)) {
      Directory(process.arguments.last).createSync(recursive: true);
      File(p.join(process.arguments.last, 'pubspec.yaml')).writeAsStringSync(_createdPubspec);
    }
    Timer.run(() {
      process
        ..emitLine('ran ${process.arguments.join(' ')}')
        ..exit(0);
    });
  }

  ProjectCreationRepositoryImpl build({String? home}) {
    final inner = scriptedStarter(ScriptedDaemonProcess.new, started: started);
    return ProjectCreationRepositoryImpl(
      database: database,
      flutterSdk: sdk,
      environment: environment,
      projectOpening: opening,
      projectTrust: trust,
      loadAsset: (key) => File(key).readAsString(),
      startProcess: (executable, arguments, {workingDirectory, environment}) async {
        final process = await inner(
          executable,
          arguments,
          workingDirectory: workingDirectory,
          environment: environment,
        ) as ScriptedDaemonProcess;
        script(process);
        return process;
      },
      home: home ?? p.join(root.path, 'home'),
    );
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('project_creation_impl_test');
    parent = Directory(p.join(root.path, 'projects'))..createSync();
    bin = p.join(root.path, 'bin');
    Directory(bin).createSync();
    File(p.join(bin, 'git')).writeAsStringSync('');
    environment = ShellEnvironment(<String, String>{'PATH': bin, 'HOME': root.path});
    database = AppDatabase(NativeDatabase.memory());
    sdk = _StubSdk();
    opening = _StubOpening();
    trust = _StubTrust();
    started = <ScriptedDaemonProcess>[];
    script = finish;
  });

  tearDown(() async {
    await database.close();
    root.deleteSync(recursive: true);
  });

  NewProjectRequest request({
    NewProjectTemplate template = NewProjectTemplate.architecture,
    bool gitInit = true,
    Set<FlutterPlatform> platforms = const <FlutterPlatform>{
      FlutterPlatform.macos,
      FlutterPlatform.ios,
      FlutterPlatform.android,
    },
  }) => NewProjectRequest(
    name: 'avera_booking',
    org: 'com.example',
    parent: parent.path,
    platforms: platforms,
    template: template,
    gitInit: gitInit,
  );

  String path() => p.join(parent.path, 'avera_booking');
  String git() => p.join(bin, 'git');

  CreationStep step(CreationRun run, CreationStepKind kind) =>
      run.steps.singleWhere((step) => step.kind == kind);

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 500 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(condition(), isTrue, reason: 'timed out');
  }

  test('is not a preview', () => expect(build().isPreview, isFalse));

  group('create', () {
    test("architecture with git runs the five steps' commands", () async {
      final runs = await build().create(request()).toList();

      expect(
        started.map(
          (process) => <Object?>[process.executable, process.arguments, process.workingDirectory],
        ),
        <List<Object?>>[
          <Object?>[
            _flutter,
            <String>[
              'create',
              '--org',
              'com.example',
              '--project-name',
              'avera_booking',
              '--platforms',
              'ios,android,macos',
              '--no-pub',
              path(),
            ],
            parent.path,
          ],
          <Object?>[
            git(),
            <String>['init'],
            path(),
          ],
          <Object?>[
            _flutter,
            <String>['pub', 'add', ...skeletonPubAddArguments],
            path(),
          ],
          <Object?>[
            _flutter,
            <String>['pub', 'get'],
            path(),
          ],
          <Object?>[
            _flutter,
            <String>['analyze'],
            path(),
          ],
          <Object?>[
            git(),
            <String>['add', '-A'],
            path(),
          ],
          <Object?>[
            git(),
            <String>['commit', '-m', 'Initial commit'],
            path(),
          ],
        ],
      );
      expect(started.map((process) => process.environment), everyElement(environment.variables));
      expect(runs.first.steps.map((step) => step.status), everyElement(CreationStepStatus.pending));
      expect(runs.last.steps.map((step) => step.kind), <CreationStepKind>[
        CreationStepKind.flutterCreate,
        CreationStepKind.gitInit,
        CreationStepKind.skeleton,
        CreationStepKind.analyze,
        CreationStepKind.firstCommit,
      ]);
      expect(runs.last.steps.map((step) => step.status), everyElement(CreationStepStatus.done));
      expect(runs.last.steps.map((step) => step.took), everyElement(isNotNull));
      expect(step(runs.last, CreationStepKind.analyze).output, <String>['ran analyze']);
      for (final run in runs) {
        expect(
          run.steps.where((step) => step.status == CreationStepStatus.running).length,
          lessThan(2),
        );
      }
    });

    test('plain without git runs create and analyze only', () async {
      final runs = await build()
          .create(request(template: NewProjectTemplate.plain, gitInit: false))
          .toList();

      expect(started.map((process) => process.arguments.first), <String>['create', 'analyze']);
      expect(started.first.arguments, isNot(contains('--no-pub')));
      expect(started.map((process) => process.executable), everyElement(_flutter));
      expect(runs.last.steps.map((step) => step.kind), <CreationStepKind>[
        CreationStepKind.flutterCreate,
        CreationStepKind.analyze,
      ]);
      expect(runs.last.steps.map((step) => step.status), everyElement(CreationStepStatus.done));
    });

    test('skeleton writes every template file filled', () async {
      final runs = await build().create(request(gitInit: false)).toList();

      for (final relative in projectTemplateFiles) {
        final file = File(p.join(path(), relative));
        expect(file.existsSync(), isTrue, reason: relative);
        expect(file.readAsStringSync(), isNot(contains('{{package}}')), reason: relative);
      }
      expect(
        File(p.join(path(), 'lib', 'main.dart')).readAsStringSync(),
        contains("import 'package:avera_booking/"),
      );
      expect(File(p.join(path(), 'l10n.yaml')).existsSync(), isTrue);
      final output = step(runs.last, CreationStepKind.skeleton).output;
      expect(output, contains('✎ lib/main.dart'));
      expect(output.where((line) => line.startsWith('✎ ')), hasLength(projectTemplateFiles.length));
    });

    test('generate true goes under flutter', () async {
      await build().create(request(gitInit: false)).toList();

      final pubspec = File(p.join(path(), 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('\nflutter:\n  generate: true\n\n  # The following line'));
      // The `flutter:` of the dependencies stays as it was.
      expect(pubspec, contains('dependencies:\n  flutter:\n    sdk: flutter\n'));
      expect('generate: true'.allMatches(pubspec), hasLength(1));
    });

    test('pubspec without flutter section fails the skeleton step', () async {
      script = (process) {
        finish(process);
        if (isCreate(process)) {
          File(p.join(process.arguments.last, 'pubspec.yaml'))
              .writeAsStringSync('name: avera_booking\n');
        }
      };
      final runs = await build().create(request(gitInit: false)).toList();

      final skeleton = step(runs.last, CreationStepKind.skeleton);
      expect(skeleton.status, CreationStepStatus.failed);
      expect(skeleton.output.last, 'pubspec.yaml has no flutter: section');
      expect(step(runs.last, CreationStepKind.analyze).status, CreationStepStatus.pending);
      expect(started.map((process) => process.arguments.first), <String>['create']);
    });

    test('failing step stops the run', () async {
      script = (process) {
        if (process.arguments.first != 'analyze') return finish(process);
        Timer.run(() {
          process
            ..emitLine('error • Undefined name')
            ..exit(1);
        });
      };
      final runs = await build().create(request()).toList();

      final analyze = step(runs.last, CreationStepKind.analyze);
      expect(analyze.status, CreationStepStatus.failed);
      expect(analyze.output, <String>['error • Undefined name']);
      expect(analyze.took, isNull);
      expect(step(runs.last, CreationStepKind.firstCommit).status, CreationStepStatus.pending);
      expect(started.map((process) => process.arguments.first), isNot(contains('commit')));
      // `flutter create` worked, so the project is added anyway.
      expect(opening.opened, <String>[path()]);
      expect(runs.last.projectId, _projectId);
    });

    test('stdout and stderr go into the output in arrival order', () async {
      script = (process) {
        if (process.arguments.first != 'analyze') return finish(process);
        Future<void>(() async {
          process.emitLine('one');
          await Future<void>.delayed(Duration.zero);
          process.emitError('two');
          await Future<void>.delayed(Duration.zero);
          process
            ..emitLine('three')
            ..exit(0);
        }).ignore();
      };
      final runs = await build()
          .create(request(template: NewProjectTemplate.plain, gitInit: false))
          .toList();

      expect(step(runs.last, CreationStepKind.analyze).output, <String>['one', 'two', 'three']);
    });

    test('a command that cannot start fails its step with the message', () async {
      final repository = ProjectCreationRepositoryImpl(
        database: database,
        flutterSdk: sdk,
        environment: environment,
        projectOpening: opening,
        projectTrust: trust,
        loadAsset: (key) => File(key).readAsString(),
        startProcess: (executable, arguments, {workingDirectory, environment}) =>
            throw const ProcessException('flutter', <String>[], 'No such file or directory'),
      );
      final runs = await repository.create(request()).toList();

      final create = step(runs.last, CreationStepKind.flutterCreate);
      expect(create.status, CreationStepStatus.failed);
      expect(create.output.last, contains('No such file or directory'));
      expect(opening.opened, isEmpty);
    });

    test('target that appeared fails flutter create', () async {
      Directory(path()).createSync();
      final runs = await build().create(request()).toList();

      expect(started, isEmpty);
      final create = step(runs.last, CreationStepKind.flutterCreate);
      expect(create.status, CreationStepStatus.failed);
      expect(create.output.last, 'The folder already exists');
      expect(
        runs.last.steps.skip(1).map((step) => step.status),
        everyElement(CreationStepStatus.pending),
      );
      expect(opening.opened, isEmpty);
    });

    test('parent that disappeared fails flutter create', () async {
      parent.deleteSync();
      final runs = await build().create(request()).toList();

      expect(started, isEmpty);
      expect(
        step(runs.last, CreationStepKind.flutterCreate).output.last,
        'The folder does not exist',
      );
    });

    test('Flutter SDK not found', () async {
      sdk.path = null;
      final runs = await build().create(request()).toList();

      expect(started, isEmpty);
      final create = step(runs.last, CreationStepKind.flutterCreate);
      expect(create.status, CreationStepStatus.failed);
      expect(create.output.last, 'Flutter SDK not found');
    });

    test('git not found', () async {
      environment = ShellEnvironment(<String, String>{'PATH': p.join(root.path, 'empty')});
      final runs = await build().create(request()).toList();

      final gitInit = step(runs.last, CreationStepKind.gitInit);
      expect(gitInit.status, CreationStepStatus.failed);
      expect(gitInit.output.last, 'git not found');
      expect(step(runs.last, CreationStepKind.skeleton).status, CreationStepStatus.pending);
      expect(started.map((process) => process.arguments.first), <String>['create']);
      expect(opening.opened, <String>[path()]);
    });

    test('stop kills the running command', () async {
      script = (process) {
        if (process.arguments.take(2).join(' ') != 'pub add') finish(process);
      };
      final repository = build();
      final runs = <CreationRun>[];
      final done = repository.create(request()).listen(runs.add).asFuture<void>();
      await until(() => started.any((process) => process.arguments.first == 'pub'));

      await repository.stop();
      await done;

      final pubAdd = started.last;
      expect(pubAdd.arguments.take(2), <String>['pub', 'add']);
      expect(pubAdd.stopped, isTrue);
      final skeleton = step(runs.last, CreationStepKind.skeleton);
      expect(skeleton.status, CreationStepStatus.failed);
      expect(skeleton.output.last, 'Stopped');
      expect(step(runs.last, CreationStepKind.analyze).status, CreationStepStatus.pending);
      expect(step(runs.last, CreationStepKind.firstCommit).status, CreationStepStatus.pending);
      expect(started, hasLength(3));
      expect(opening.opened, <String>[path()]);
      expect(runs.last.projectId, _projectId);
    });

    test('stop never throws', () async {
      script = (process) {
        if (process.arguments.first != 'analyze') return finish(process);
        process.stopError = StateError('the group would not die');
      };
      final repository = build();
      final runs = <CreationRun>[];
      final done = repository
          .create(request(template: NewProjectTemplate.plain, gitInit: false))
          .listen(runs.add)
          .asFuture<void>();
      await until(() => started.length == 2);

      await repository.stop();
      await done;

      expect(step(runs.last, CreationStepKind.analyze).output.last, 'Stopped');
      // Nothing is running.
      await repository.stop();
      await repository.dispose();
    });

    test('cancel kills and adds nothing', () async {
      script = (process) {
        if (process.arguments.first != 'analyze') finish(process);
      };
      final subscription = build().create(request()).listen(null);
      await until(() => started.any((process) => process.arguments.first == 'analyze'));

      await subscription.cancel();

      expect(started.last.stopped, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(started.last.arguments, <String>['analyze']);
      expect(opening.opened, isEmpty);
      expect(trust.trusted, isEmpty);
    });

    test('dispose kills the running command', () async {
      script = (process) {
        if (process.arguments.first != 'analyze') finish(process);
      };
      final repository = build();
      final runs = <CreationRun>[];
      final done = repository.create(request()).listen(runs.add).asFuture<void>();
      await until(() => started.any((process) => process.arguments.first == 'analyze'));
      final before = runs.length;

      await repository.dispose();
      await done;

      expect(started.last.stopped, isTrue);
      expect(started.last.arguments, <String>['analyze']);
      expect(runs, hasLength(before));
      expect(opening.opened, isEmpty);
    });

    test('output is bounded', () async {
      script = (process) {
        if (process.arguments.first != 'analyze') return finish(process);
        Timer.run(() {
          for (var i = 1; i <= 1000; i++) {
            process.emitLine('line $i');
          }
          process.exit(0);
        });
      };
      final runs = await build()
          .create(request(template: NewProjectTemplate.plain, gitInit: false))
          .toList();

      final output = step(runs.last, CreationStepKind.analyze).output;
      expect(output, hasLength(kCreationOutputKept));
      expect(kCreationOutputKept, 200);
      expect(output.first, 'line 801');
      expect(output.last, 'line 1000');
    });

    test('success adds and trusts the project', () async {
      final runs = await build().create(request()).toList();

      expect(opening.opened, <String>[path()]);
      expect(trust.trusted, <int>[_projectId]);
      expect(runs.last.projectId, _projectId);
      expect(runs.reversed.skip(1).map((run) => run.projectId), everyElement(isNull));
      expect(runs.last.steps.map((step) => step.status), everyElement(CreationStepStatus.done));
    });

    test('flutter create failure adds nothing', () async {
      script = (process) {
        if (!isCreate(process)) return finish(process);
        Timer.run(() {
          process
            ..emitError('Could not create')
            ..exit(1);
        });
      };
      final runs = await build().create(request()).toList();

      expect(step(runs.last, CreationStepKind.flutterCreate).status, CreationStepStatus.failed);
      expect(runs.map((run) => run.projectId), everyElement(isNull));
      expect(opening.opened, isEmpty);
      expect(trust.trusted, isEmpty);
      expect(started, hasLength(1));
    });

    test('a failure to add the project is a stream error', () async {
      opening.error = const FileSystemException('Folder does not exist');

      await expectLater(
        build().create(request(template: NewProjectTemplate.plain, gitInit: false)),
        emitsThrough(emitsError(isA<FileSystemException>())),
      );
      expect(trust.trusted, isEmpty);
    });
  });

  Future<void> addProject(String path, DateTime? openedAt) => database
      .into(database.projectsTable)
      .insert(
        ProjectsTableCompanion.insert(
          path: path,
          name: p.basename(path),
          lastOpenedAt: .new(openedAt),
        ),
      );

  group('checkTarget', () {
    test('a free name', () async {
      expect(await build().checkTarget(root.path, 'app'), isNull);
    });

    test('an existing empty folder', () async {
      Directory(p.join(root.path, 'app')).createSync();
      expect(await build().checkTarget(root.path, 'app'), TargetProblem.exists);
    });

    test('an existing file', () async {
      File(p.join(root.path, 'app')).writeAsStringSync('');
      expect(await build().checkTarget(root.path, 'app'), TargetProblem.exists);
    });

    test('a missing parent', () async {
      expect(
        await build().checkTarget(p.join(root.path, 'nope'), 'app'),
        TargetProblem.parentMissing,
      );
    });
  });

  group('defaultParent', () {
    test('prefers the last opened project', () async {
      final older = Directory(p.join(root.path, 'older'))..createSync();
      final newer = Directory(p.join(root.path, 'newer'))..createSync();
      await addProject(p.join(older.path, 'a'), DateTime(2026, 1, 1));
      await addProject(p.join(newer.path, 'b'), DateTime(2026, 2, 1));
      await addProject(p.join(root.path, 'never', 'c'), null);
      expect(await build().defaultParent(), newer.path);
    });

    test("falls back to home when the last project's parent is gone", () async {
      await addProject(p.join(root.path, 'gone', 'a'), DateTime(2026, 1, 1));
      Directory(p.join(root.path, 'home')).createSync();
      expect(await build().defaultParent(), p.join(root.path, 'home'));
    });

    test('falls back to home when the projects cannot be read', () async {
      await database.customStatement('DROP TABLE ${database.projectsTable.actualTableName}');
      expect(await build().defaultParent(), p.join(root.path, 'home'));
    });

    test('without projects: ~/StudioProjects if it exists, else home', () async {
      final home = p.join(root.path, 'home');
      Directory(home).createSync();
      expect(await build().defaultParent(), home);
      Directory(p.join(home, 'StudioProjects')).createSync();
      expect(await build().defaultParent(), p.join(home, 'StudioProjects'));
    });
  });
}
