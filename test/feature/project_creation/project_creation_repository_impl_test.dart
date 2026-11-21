import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_template.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_member_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/scripted_daemon_process.dart';

const String _flutter = '/sdk/bin/flutter';

/// A `pubspec.yaml` as `flutter create` writes it, cut down.
const String _createdPubspec = '''
name: avera_booking
description: "A new Flutter project."

environment:
  sdk: ^3.10.4

dependencies:
  flutter:
    sdk: flutter

# The following section is specific to Flutter packages.
flutter:

  # The following line ensures that the Material Icons font is
  # included with your application.
  uses-material-design: true
''';

void main() {
  late Directory root;
  late Directory parent;
  late String bin;
  late AppDatabase database;

  /// What the `flutter` function returns.
  late String? flutterPath;

  /// The rule names `writeRules` writes; it creates `docs/rules` when there is any.
  late List<String> ruleNames;

  /// Every project path `writeRules` was called with.
  late List<String> rulesWritten;

  Future<List<String>> writeRules(String projectPath) async {
    rulesWritten.add(projectPath);
    if (ruleNames.isNotEmpty) {
      Directory(p.join(projectPath, 'docs', 'rules')).createSync(recursive: true);
    }
    return ruleNames;
  }

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

  /// What the `dartVersion` function returns.
  late String? dartVersion;

  /// What the `flutterVersion` function returns.
  late String? flutterVersion;

  ProjectCreationRepositoryImpl build({String? home}) {
    final inner = scriptedStarter(ScriptedDaemonProcess.new, started: started);
    return ProjectCreationRepositoryImpl(
      database: database,
      flutter: () async => flutterPath,
      environment: environment,
      writeRules: writeRules,
      loadAsset: (key) => File(key).readAsString(),
      now: () => DateTime(2026, 11, 6),
      dartVersion: () async => dartVersion,
      flutterVersion: () async => flutterVersion,
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
    flutterPath = _flutter;
    dartVersion = '3.14.0';
    flutterVersion = '3.50.0';
    ruleNames = <String>['a'];
    rulesWritten = <String>[];
    started = <ScriptedDaemonProcess>[];
    script = finish;
  });

  tearDown(() async {
    await database.close();
    root.deleteSync(recursive: true);
  });

  NewProjectRequest request({
    FlutterProjectType type = FlutterProjectType.app,
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
    type: type,
    template: template,
    gitInit: gitInit,
  );

  NewProjectRequest monorepo({
    NewProjectTemplate template = NewProjectTemplate.architecture,
    bool gitInit = false,
  }) => NewProjectRequest(
    name: 'shop',
    org: 'com.example',
    parent: parent.path,
    template: template,
    gitInit: gitInit,
    structure: ProjectStructure.monorepo,
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
              '--template',
              'app',
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
            <String>['pub', 'add', 'material_ui'],
            p.join(path(), 'packages', 'ui'),
          ],
          <Object?>[
            _flutter,
            <String>['pub', 'get'],
            path(),
          ],
          <Object?>[
            p.join(p.dirname(_flutter), 'dart'),
            <String>['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
            path(),
          ],
          <Object?>[
            p.join(p.dirname(_flutter), 'dart'),
            <String>['fix', '--apply', '--code=directives_ordering'],
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
        CreationStepKind.rules,
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
        CreationStepKind.rules,
      ]);
      expect(runs.last.steps.map((step) => step.status), everyElement(CreationStepStatus.done));
    });

    test('a package is created with its template, no platforms and no skeleton', () async {
      final runs = await build()
          .create(request(type: FlutterProjectType.package, gitInit: false))
          .toList();

      expect(started.first.arguments, <String>[
        'create',
        '--template',
        'package',
        '--org',
        'com.example',
        '--project-name',
        'avera_booking',
        path(),
      ]);
      expect(started.map((process) => process.arguments.first), <String>['create', 'analyze']);
      expect(runs.last.steps.map((step) => step.kind), <CreationStepKind>[
        CreationStepKind.flutterCreate,
        CreationStepKind.analyze,
        CreationStepKind.rules,
      ]);
    });

    test('a plugin gets its platforms; an FFI package and a module get none', () async {
      await build().create(request(type: FlutterProjectType.plugin, gitInit: false)).toList();
      expect(started.first.arguments, containsAllInOrder(<String>['--template', 'plugin']));
      expect(
        started.first.arguments,
        containsAllInOrder(<String>['--platforms', 'ios,android,macos']),
      );
      expect(started.first.arguments, isNot(contains('--no-pub')));

      for (final (type, template) in const <(FlutterProjectType, String)>[
        (FlutterProjectType.packageFfi, 'package_ffi'),
        (FlutterProjectType.module, 'module'),
      ]) {
        started.clear();
        Directory(path()).deleteSync(recursive: true);
        await build().create(request(type: type, gitInit: false)).toList();
        expect(started.first.arguments, containsAllInOrder(<String>['--template', template]));
        expect(started.first.arguments, isNot(contains('--platforms')), reason: template);
      }
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
      expect(File(p.join(path(), 'Makefile')).existsSync(), isTrue);
      expect(
        File(p.join(path(), 'CHANGELOG.md')).readAsStringSync(),
        contains('## [1.0.0] - 2026-11-06'),
      );
      expect(
        File(p.join(path(), 'lib', '_core', 'localization', 'intl_en.arb')).existsSync(),
        isTrue,
      );
      final output = step(runs.last, CreationStepKind.skeleton).output;
      expect(output, contains('✎ lib/main.dart'));
      expect(output.where((line) => line.startsWith('✎ ')), hasLength(projectTemplateFiles.length));
    });

    test('generate true goes under flutter', () async {
      await build().create(request(gitInit: false)).toList();

      final pubspec = File(p.join(path(), 'pubspec.yaml')).readAsStringSync();
      expect(
        pubspec,
        contains(
          '\nflutter:\n  generate: true\n\n'
          '  # The shimmer of packages/ui loads it as `packages/ui/shaders/shimmer.frag`.\n'
          '  shaders:\n    - packages/ui/shaders/shimmer.frag\n\n  # The following line',
        ),
      );
      // `packages/ui` is a workspace member, declared right before the dependencies.
      expect(pubspec, contains('workspace:\n  - packages/ui\n\ndependencies:\n'));
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
        flutter: () async => flutterPath,
        environment: environment,
        writeRules: writeRules,
        loadAsset: (key) => File(key).readAsString(),
        flutterVersion: () async => flutterVersion,
        startProcess: (executable, arguments, {workingDirectory, environment}) =>
            throw const ProcessException('flutter', <String>[], 'No such file or directory'),
      );
      final runs = await repository.create(request()).toList();

      final create = step(runs.last, CreationStepKind.flutterCreate);
      expect(create.status, CreationStepStatus.failed);
      expect(create.output.last, contains('No such file or directory'));
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
      flutterPath = null;
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

    test('cancel kills the command', () async {
      script = (process) {
        if (process.arguments.first != 'analyze') finish(process);
      };
      final subscription = build().create(request()).listen(null);
      await until(() => started.any((process) => process.arguments.first == 'analyze'));

      await subscription.cancel();

      expect(started.last.stopped, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(started.last.arguments, <String>['analyze']);
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

    test('the rules step writes the rules before the first commit and lists them', () async {
      bool? rulesAtAdd;
      script = (process) {
        if (process.executable == git() && process.arguments.first == 'add') {
          rulesAtAdd = Directory(p.join(path(), 'docs', 'rules')).existsSync();
        }
        finish(process);
      };

      final runs = await build().create(request()).toList();

      expect(rulesWritten, <String>[path()]);
      expect(rulesAtAdd, isTrue);
      expect(step(runs.last, CreationStepKind.rules).output, <String>['✎ docs/rules/a.md']);
      final kinds = runs.last.steps.map((step) => step.kind).toList();
      expect(
        kinds.indexOf(CreationStepKind.rules),
        kinds.indexOf(CreationStepKind.firstCommit) - 1,
      );
    });

    test('no rule written lists nothing', () async {
      ruleNames = const <String>[];

      final runs = await build().create(request()).toList();

      expect(step(runs.last, CreationStepKind.rules).output, isEmpty);
      expect(step(runs.last, CreationStepKind.rules).status, CreationStepStatus.done);
    });

    test('flutter create failure runs nothing else', () async {
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
      expect(started, hasLength(1));
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

  group('monorepo', () {
    String root() => p.join(parent.path, 'shop');
    String read(String relative) =>
        File(p.joinAll(<String>[root(), ...relative.split('/')])).readAsStringSync();
    bool exists(String relative) =>
        FileSystemEntity.typeSync(p.joinAll(<String>[root(), ...relative.split('/')])) !=
        FileSystemEntityType.notFound;
    Future<String> asset(String key) => File(key).readAsString();

    test('monorepo workspace step writes the root', () async {
      final runs = await build().create(monorepo(template: NewProjectTemplate.plain)).toList();

      expect(step(runs.last, CreationStepKind.workspace).status, CreationStepStatus.done);
      expect(read('pubspec.yaml'), monorepoRootPubspec(name: 'shop', sdkConstraint: '^3.14.0'));
      for (final relative in monorepoTemplateFiles) {
        expect(read(relative), await asset('$monorepoTemplateRoot$relative'), reason: relative);
      }
      expect(
        read('analysis_options.yaml'),
        await asset('${projectTemplateRoot}analysis_options.yaml'),
      );
      expect(read('CHANGELOG.md'), contains('## [1.0.0] - 2026-11-06'));
      expect(exists('tool/dart/rename_project.dart'), isFalse);
      expect(exists('lib'), isFalse);
      expect(read('.gitignore'), contains('.dart_tool/'));
    });

    test('monorepo flutter create runs in apps/<folder>', () async {
      await build().create(monorepo(template: NewProjectTemplate.plain)).toList();

      expect(started.first.arguments, <String>[
        'create',
        '--template',
        'app',
        '--org',
        'com.example',
        '--project-name',
        'shop_app',
        '--platforms',
        'ios,android,macos',
        '--no-pub',
        p.join(root(), 'apps', 'app'),
      ]);
      expect(started.first.workingDirectory, root());
    });

    test('member pubspec joins the workspace', () async {
      await build().create(monorepo(template: NewProjectTemplate.plain)).toList();

      final pubspec = read('apps/app/pubspec.yaml');
      expect(pubspec, contains('environment:\n  sdk: ^3.14.0\n\nresolution: workspace\n'));
      expect(pubspec, isNot(contains('^3.10.4')));
    });

    test('monorepo skeleton', () async {
      final runs = await build().create(monorepo()).toList();

      expect(runs.last.steps.map((step) => step.status), everyElement(CreationStepStatus.done));
      expect(exists('apps/app/lib/main.dart'), isTrue);
      expect(exists('apps/app/lib/_core/utils/api_client.dart'), isTrue);
      expect(exists('lib'), isFalse);
      expect(read('apps/app/lib/main.dart'), contains("import 'package:shop_app/"));
      for (final relative in projectTemplateUiFiles) {
        expect(exists(relative), isTrue, reason: relative);
      }
      final pubspec = read('apps/app/pubspec.yaml');
      expect(pubspec, contains('\nflutter:\n  generate: true\n\n'));
      expect(pubspec, isNot(contains('shaders:')));
      expect(pubspec, isNot(contains('workspace:\n  - packages/ui')));
      // packages/ui keeps its template's SDK constraint: on the root's (3.14 and newer) its
      // private fields trip `prefer_initializing_formals`, which the one-app template must not
      // change for. A workspace resolves members with different lower bounds.
      final ui = read('packages/ui/pubspec.yaml');
      expect(ui, contains('environment:\n  sdk: ^3.10.4\n'));
      expect(ui, isNot(contains('^3.14.0')));
      expect('resolution: workspace'.allMatches(ui), hasLength(1));
      expect(ui, contains('shaders/shimmer.frag'));
      expect(
        step(runs.last, CreationStepKind.skeleton).output,
        containsAll(<String>['✎ apps/app/lib/main.dart', '✎ packages/ui/lib/ui.dart']),
      );

      final dart = p.join(p.dirname(_flutter), 'dart');
      expect(
        started
            .skip(1)
            .map(
              (process) => <Object?>[
                process.executable,
                process.arguments,
                process.workingDirectory,
              ],
            ),
        <List<Object?>>[
          <Object?>[
            _flutter,
            <String>['pub', 'add', ...skeletonPubAddArgumentsFor(uiPath: '../../packages/ui')],
            p.join(root(), 'apps', 'app'),
          ],
          <Object?>[
            _flutter,
            <String>['pub', 'add', 'material_ui'],
            p.join(root(), 'packages', 'ui'),
          ],
          <Object?>[
            _flutter,
            <String>['pub', 'add', 'dev:build_runner'],
            root(),
          ],
          <Object?>[
            _flutter,
            <String>['pub', 'get'],
            root(),
          ],
          <Object?>[
            dart,
            <String>['run', 'build_runner', 'build', '--workspace', '--delete-conflicting-outputs'],
            root(),
          ],
          <Object?>[
            dart,
            <String>['fix', '--apply', '--code=directives_ordering'],
            root(),
          ],
          <Object?>[
            _flutter,
            <String>['analyze'],
            root(),
          ],
        ],
      );
    });

    test('monorepo target check', () async {
      Directory(root()).createSync();
      final runs = await build().create(monorepo()).toList();

      final workspace = step(runs.last, CreationStepKind.workspace);
      expect(workspace.status, CreationStepStatus.failed);
      expect(workspace.output.last, 'The folder already exists');
      expect(started, isEmpty);

      Directory(root()).deleteSync();
      started.clear();
      final again = await build().create(monorepo(template: NewProjectTemplate.plain)).toList();
      expect(again.last.steps.map((step) => step.status), everyElement(CreationStepStatus.done));
      expect(started.first.arguments.first, 'create');
      expect(started.first.arguments.last, p.join(root(), 'apps', 'app'));
    });

    test('members inherit the root analysis options', () async {
      await build().create(monorepo(template: NewProjectTemplate.plain)).toList();

      expect(read('apps/app/analysis_options.yaml'), 'include: ../../analysis_options.yaml\n');
    });

    test('empty monorepo runs pub get in the root', () async {
      final runs = await build().create(monorepo(template: NewProjectTemplate.plain)).toList();

      expect(runs.last.steps.map((step) => step.kind), <CreationStepKind>[
        CreationStepKind.workspace,
        CreationStepKind.flutterCreate,
        CreationStepKind.pubGet,
        CreationStepKind.analyze,
        CreationStepKind.rules,
      ]);
      expect(runs.last.steps.map((step) => step.status), everyElement(CreationStepStatus.done));
      expect(started.map((process) => process.arguments.join(' ')), contains('pub get'));
      expect(started[1].workingDirectory, root());
      expect(exists('packages/ui'), isFalse);
    });

    test('unknown Dart version fails the workspace step', () async {
      dartVersion = null;
      final runs = await build().create(monorepo()).toList();

      final workspace = step(runs.last, CreationStepKind.workspace);
      expect(workspace.status, CreationStepStatus.failed);
      expect(workspace.output.last, 'Dart version unknown');
      expect(exists('pubspec.yaml'), isFalse);
    });

    test('sdk constraint comes from the SDKs Dart', () async {
      dartVersion = '3.15.2';
      await build().create(monorepo(template: NewProjectTemplate.plain)).toList();

      expect(read('pubspec.yaml'), contains('sdk: ^3.15.0'));
      expect(read('apps/app/pubspec.yaml'), contains('sdk: ^3.15.0'));
    });
  });

  group('add member', () {
    const lockBefore = 'lock before\n';

    /// What the fake `git check-ignore -q pubspec.lock` answers.
    var lockIgnored = false;
    String root() => p.join(parent.path, 'shop');
    String file(String relative) => p.joinAll(<String>[root(), ...relative.split('/')]);
    String read(String relative) => File(file(relative)).readAsStringSync();
    bool exists(String relative) =>
        FileSystemEntity.typeSync(file(relative)) != FileSystemEntityType.notFound;
    String dart() => p.join(p.dirname(_flutter), 'dart');

    /// A monorepo on disk: the root `pubspec.yaml` (with `build_runner` when [buildRunner]),
    /// `packages/ui` and, when [lock], a `pubspec.lock`.
    void monorepoOnDisk({bool buildRunner = true, bool lock = true}) {
      Directory(file('packages/ui')).createSync(recursive: true);
      File(file('pubspec.yaml')).writeAsStringSync(
        '${monorepoRootPubspec(name: 'shop', sdkConstraint: '^3.14.0')}'
        '${buildRunner ? '\ndev_dependencies:\n  build_runner: ^2.11.0\n' : ''}',
      );
      File(file('packages/ui/pubspec.yaml')).writeAsStringSync('name: ui\n');
      if (lock) File(file('pubspec.lock')).writeAsStringSync(lockBefore);
    }

    NewMemberRequest member({
      MemberKind kind = MemberKind.flutterApp,
      String folder = 'admin',
      NewProjectTemplate template = NewProjectTemplate.architecture,
      bool gitRepo = true,
    }) => NewMemberRequest(
      projectId: 1,
      projectPath: root(),
      kind: kind,
      folder: folder,
      packageName: 'shop_$folder',
      org: 'com.example',
      platforms: const <FlutterPlatform>{FlutterPlatform.macos},
      template: template,
      gitRepo: gitRepo,
    );

    bool isPub(ScriptedDaemonProcess process) => process.arguments.first == 'pub';

    /// [finish], with `dart create` writing its `pubspec.yaml` and `bin/` and every `pub` command
    /// rewriting the root's lock, the way a resolution does.
    void resolving(ScriptedDaemonProcess process) {
      if (process.executable == dart() && process.arguments.first == 'create') {
        final dir = process.arguments.last;
        final name = p.basename(dir);
        Directory(p.join(dir, 'bin')).createSync(recursive: true);
        Directory(p.join(dir, '.dart_tool')).createSync(recursive: true);
        File(p.join(dir, 'pubspec.yaml')).writeAsStringSync(
          'name: $name\n\nenvironment:\n  sdk: ^3.10.4\n\ndependencies:\n  path: ^1.0.0\n',
        );
        File(p.join(dir, 'bin', '$name.dart'))
            .writeAsStringSync("import 'package:$name/$name.dart';\n");
        File(p.join(dir, '.dart_tool', 'x.dart'))
            .writeAsStringSync("import 'package:$name/$name.dart';\n");
        File(p.join(dir, 'analysis_options.yaml'))
            .writeAsStringSync('include: package:lints/recommended.yaml\n');
      }
      if (isPub(process)) File(file('pubspec.lock')).writeAsStringSync('lock after\n');
      if (process.executable == git() && process.arguments.first == 'check-ignore') {
        // `check-ignore -q` prints nothing: 0 is ignored, 1 is not.
        Timer.run(() => process.exit(lockIgnored ? 0 : 1));
        return;
      }
      finish(process);
    }

    /// Runs real git in the root and expects it to succeed; returns its stdout.
    String gitIn(List<String> arguments) {
      final result = Process.runSync('git', arguments, workingDirectory: root());
      expect(result.exitCode, 0, reason: '${arguments.join(' ')}: ${result.stderr}');
      return '${result.stdout}';
    }

    /// Makes the root a real git repository with everything in it committed, and lets the fake
    /// git run the real one.
    void realGit() {
      gitIn(<String>['init', '-q']);
      gitIn(<String>['config', 'user.email', 'test@example.com']);
      gitIn(<String>['config', 'user.name', 'Test']);
      gitIn(<String>['config', 'commit.gpgsign', 'false']);
      gitIn(<String>['add', '-A']);
      gitIn(<String>['commit', '-q', '-m', 'Initial commit']);
      script = (process) {
        if (process.executable != git()) return resolving(process);
        final result = Process.runSync(
          'git',
          process.arguments,
          workingDirectory: process.workingDirectory,
        );
        Timer.run(() => process.exit(result.exitCode));
      };
    }

    /// The subject and files of the last commit.
    List<String> lastCommit() =>
        gitIn(<String>['show', '--name-only', '--format=%s', 'HEAD']).trim().split('\n');

    final noGit = Process.runSync('git', <String>['--version']).exitCode == 0 ? false : 'no git';

    /// The processes started, as `[executable, arguments, workingDirectory]`.
    List<List<Object?>> commands() => <List<Object?>>[
      for (final process in started)
        <Object?>[process.executable, process.arguments, process.workingDirectory],
    ];

    setUp(() {
      monorepoOnDisk();
      lockIgnored = false;
      script = resolving;
    });

    test('add flutter app with the skeleton', () async {
      final runs = await build().addMember(member()).toList();

      expect(runs.first.steps.map((step) => step.status), everyElement(CreationStepStatus.pending));
      expect(runs.last.steps.map((step) => step.kind), <CreationStepKind>[
        CreationStepKind.memberCreate,
        CreationStepKind.skeleton,
        CreationStepKind.commit,
        CreationStepKind.analyze,
      ]);
      expect(runs.last.steps.map((step) => step.status), everyElement(CreationStepStatus.done));
      final admin = file('apps/admin');
      expect(commands(), <List<Object?>>[
        <Object?>[
          _flutter,
          <String>[
            'create',
            '--template',
            'app',
            '--org',
            'com.example',
            '--project-name',
            'shop_admin',
            '--platforms',
            'macos',
            '--no-pub',
            admin,
          ],
          root(),
        ],
        <Object?>[
          _flutter,
          <String>['pub', 'add', ...skeletonPubAddArgumentsFor(uiPath: '../../packages/ui')],
          admin,
        ],
        <Object?>[
          _flutter,
          <String>['pub', 'get'],
          root(),
        ],
        <Object?>[
          dart(),
          <String>['run', 'build_runner', 'build', '--workspace', '--delete-conflicting-outputs'],
          root(),
        ],
        <Object?>[
          dart(),
          <String>['fix', '--apply', '--code=directives_ordering'],
          admin,
        ],
        <Object?>[
          git(),
          <String>['check-ignore', '-q', 'pubspec.lock'],
          root(),
        ],
        <Object?>[
          git(),
          <String>['add', 'apps/admin', 'pubspec.lock'],
          root(),
        ],
        <Object?>[
          git(),
          <String>['commit', '-m', 'Add Flutter app admin', '--', 'apps/admin', 'pubspec.lock'],
          root(),
        ],
        <Object?>[
          _flutter,
          <String>['analyze'],
          admin,
        ],
      ]);
      expect(
        skeletonPubAddArgumentsFor(uiPath: '../../packages/ui'),
        contains('ui@{path: ../../packages/ui}'),
      );
      expect(read('apps/admin/lib/main.dart'), contains("import 'package:shop_admin/"));
      expect(
        step(runs.last, CreationStepKind.skeleton).output,
        contains('✎ apps/admin/lib/main.dart'),
      );
      final pubspec = read('apps/admin/pubspec.yaml');
      expect(pubspec, contains('environment:\n  sdk: ^3.14.0\n\nresolution: workspace\n'));
      expect(pubspec, contains('\nflutter:\n  generate: true\n\n'));
      expect(read('apps/admin/analysis_options.yaml'), 'include: ../../analysis_options.yaml\n');
      expect(read('pubspec.lock'), 'lock after\n');
    });

    test('without build_runner in the root it builds the member alone', () async {
      monorepoOnDisk(buildRunner: false);
      await build().addMember(member(gitRepo: false)).toList();

      expect(
        commands(),
        anyElement(
          equals(<Object?>[
            dart(),
            <String>['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
            file('apps/admin'),
          ]),
        ),
      );
      expect(read('pubspec.yaml'), isNot(contains('build_runner')));
    });

    test('add dart package', () async {
      // The root's constraint wins over the Dart of the SDK.
      dartVersion = '3.15.2';
      final runs = await build()
          .addMember(member(kind: MemberKind.dartPackage, folder: 'core', gitRepo: false))
          .toList();

      expect(runs.last.steps.map((step) => step.kind), <CreationStepKind>[
        CreationStepKind.memberCreate,
        CreationStepKind.pubGet,
        CreationStepKind.analyze,
      ]);
      expect(runs.last.steps.map((step) => step.status), everyElement(CreationStepStatus.done));
      final core = file('packages/core');
      expect(commands(), <List<Object?>>[
        <Object?>[
          dart(),
          <String>['create', '-t', 'package', '--no-pub', core],
          root(),
        ],
        <Object?>[
          _flutter,
          <String>['pub', 'get'],
          root(),
        ],
        <Object?>[
          _flutter,
          <String>['analyze'],
          core,
        ],
      ]);
      final pubspec = read('packages/core/pubspec.yaml');
      expect(pubspec, startsWith('name: shop_core\n'));
      expect(pubspec, contains('sdk: ^3.14.0\n\nresolution: workspace\n'));
    });

    test('a Dart app is renamed and its imports follow', () async {
      await build()
          .addMember(member(kind: MemberKind.dartApp, folder: 'server', gitRepo: false))
          .toList();

      final server = file('apps/server');
      expect(started.first.arguments, <String>['create', '-t', 'console', '--no-pub', server]);
      expect(started.first.workingDirectory, root());
      expect(read('apps/server/pubspec.yaml'), startsWith('name: shop_server\n'));
      expect(read('apps/server/bin/server.dart'), "import 'package:shop_server/server.dart';\n");
      expect(read('apps/server/.dart_tool/x.dart'), contains('package:server/'));
      expect(read('apps/server/analysis_options.yaml'), 'include: ../../analysis_options.yaml\n');
    });

    // The member inherits the root's `avoid_print`: the `print` of the samples `dart create`
    // writes failed the add's `flutter analyze`.
    test('the samples of a Dart member write to stdout instead of print', () async {
      script = (process) {
        if (process.executable == dart() && process.arguments.first == 'create') {
          final dir = process.arguments.last;
          final name = p.basename(dir);
          Directory(p.join(dir, 'example')).createSync(recursive: true);
          Directory(p.join(dir, 'lib')).createSync(recursive: true);
          File(p.join(dir, 'example', '${name}_example.dart')).writeAsStringSync(
            "import 'package:$name/$name.dart';\n\nvoid main() {\n  print('awesome');\n}\n",
          );
          File(p.join(dir, 'lib', '$name.dart')).writeAsStringSync("// print('x');\n");
        }
        resolving(process);
      };

      await build()
          .addMember(member(kind: MemberKind.dartApp, folder: 'server', gitRepo: false))
          .toList();
      await build()
          .addMember(member(kind: MemberKind.dartPackage, folder: 'core', gitRepo: false))
          .toList();

      expect(
        read('apps/server/example/server_example.dart'),
        "import 'dart:io';\n\nimport 'package:shop_server/server.dart';\n\n"
        "void main() {\n  stdout.writeln('awesome');\n}\n",
      );
      expect(
        read('packages/core/example/core_example.dart'),
        contains("stdout.writeln('awesome')"),
      );
      // Only the samples a member runs are touched, and a file without `print` stays as it was.
      expect(read('apps/server/lib/server.dart'), "// print('x');\n");
      expect(read('apps/server/bin/server.dart'), "import 'package:shop_server/server.dart';\n");
    });

    test('commit stages only the member', () async {
      final runs = await build().addMember(member(template: NewProjectTemplate.plain)).toList();

      expect(step(runs.last, CreationStepKind.commit).status, CreationStepStatus.done);
      expect(
        started.where((process) => process.executable == git()).map((process) => process.arguments),
        <List<String>>[
          <String>['check-ignore', '-q', 'pubspec.lock'],
          <String>['add', 'apps/admin', 'pubspec.lock'],
          // The pathspec keeps what the user had staged out of the commit.
          <String>['commit', '-m', 'Add Flutter app admin', '--', 'apps/admin', 'pubspec.lock'],
        ],
      );
    });

    test('a file staged before the add stays staged and out of the commit', () async {
      realGit();
      File(file('notes.txt')).writeAsStringSync('mine\n');
      gitIn(<String>['add', 'notes.txt']);

      final runs = await build().addMember(member(template: NewProjectTemplate.plain)).toList();

      expect(step(runs.last, CreationStepKind.commit).status, CreationStepStatus.done);
      final committed = lastCommit();
      expect(committed.first, 'Add Flutter app admin');
      expect(committed, containsAll(<String>['apps/admin/pubspec.yaml', 'pubspec.lock']));
      expect(committed, isNot(contains('notes.txt')));
      expect(gitIn(<String>['diff', '--cached', '--name-only']), 'notes.txt\n');
    }, skip: noGit);

    test('a repository that ignores pubspec.lock gets the member alone', () async {
      File(file('pubspec.lock')).deleteSync();
      File(file('.gitignore')).writeAsStringSync('pubspec.lock\n');
      realGit();

      final runs = await build().addMember(member(template: NewProjectTemplate.plain)).toList();

      expect(runs.last.steps.map((step) => step.status), everyElement(CreationStepStatus.done));
      final committed = lastCommit();
      expect(committed.first, 'Add Flutter app admin');
      expect(committed, contains('apps/admin/pubspec.yaml'));
      expect(committed, isNot(contains('pubspec.lock')));
      expect(gitIn(<String>['status', '--porcelain']), isEmpty);
      expect(read('pubspec.lock'), 'lock after\n');
    }, skip: noGit);

    test('a tracked pubspec.lock is committed even when .gitignore lists it', () async {
      realGit();
      File(file('.gitignore')).writeAsStringSync('pubspec.lock\n');
      gitIn(<String>['add', '.gitignore']);
      gitIn(<String>['commit', '-q', '-m', 'Ignore the lock']);

      await build().addMember(member(template: NewProjectTemplate.plain)).toList();

      expect(lastCommit(), containsAll(<String>['apps/admin/pubspec.yaml', 'pubspec.lock']));
    }, skip: noGit);

    test('stop rolls back', () async {
      script = (process) {
        if (isCreate(process)) {
          // Half made: the folder is there, the command never ends.
          Directory(process.arguments.last).createSync(recursive: true);
          File(p.join(process.arguments.last, 'pubspec.yaml')).writeAsStringSync(_createdPubspec);
          return;
        }
        resolving(process);
      };
      final repository = build();
      final runs = <CreationRun>[];
      final done = repository.addMember(member()).listen(runs.add).asFuture<void>();
      await until(() => started.isNotEmpty);

      await repository.stop();
      await done;

      final create = step(runs.last, CreationStepKind.memberCreate);
      expect(create.status, CreationStepStatus.failed);
      expect(create.output, containsAllInOrder(<String>['Stopped', 'Removed apps/admin']));
      expect(create.output.last, 'Removed apps/admin');
      expect(exists('apps/admin'), isFalse);
      expect(read('pubspec.lock'), lockBefore);
      expect(started, hasLength(1));
    });

    test('a failed step before commit rolls back', () async {
      script = (process) {
        if (!isPub(process)) return resolving(process);
        File(file('pubspec.lock')).writeAsStringSync('half resolved\n');
        Timer.run(() {
          process
            ..emitError('Because shop_admin depends on nothing that exists...')
            ..exit(1);
        });
      };
      final runs = await build().addMember(member(template: NewProjectTemplate.plain)).toList();

      final pubGet = step(runs.last, CreationStepKind.pubGet);
      expect(pubGet.status, CreationStepStatus.failed);
      expect(pubGet.output, <String>[
        'Because shop_admin depends on nothing that exists...',
        'Removed apps/admin',
      ]);
      expect(step(runs.last, CreationStepKind.commit).status, CreationStepStatus.pending);
      expect(exists('apps/admin'), isFalse);
      expect(exists('apps'), isTrue);
      expect(exists('packages/ui/pubspec.yaml'), isTrue);
      expect(read('pubspec.lock'), lockBefore);
      expect(started.map((process) => process.executable), isNot(contains(git())));
    });

    test('rollback deletes a lock that was not there before', () async {
      File(file('pubspec.lock')).deleteSync();
      script = (process) {
        if (!isPub(process)) return resolving(process);
        File(file('pubspec.lock')).writeAsStringSync('half resolved\n');
        Timer.run(() => process.exit(1));
      };
      await build().addMember(member(template: NewProjectTemplate.plain)).toList();

      expect(exists('apps/admin'), isFalse);
      expect(exists('pubspec.lock'), isFalse);
    });

    test('a failed commit rolls back', () async {
      script = (process) {
        if (process.executable != git() || process.arguments.first != 'commit') {
          return resolving(process);
        }
        Timer.run(() {
          process
            ..emitError('Author identity unknown')
            ..exit(128);
        });
      };
      final runs = await build().addMember(member(template: NewProjectTemplate.plain)).toList();

      expect(step(runs.last, CreationStepKind.commit).status, CreationStepStatus.failed);
      expect(step(runs.last, CreationStepKind.commit).output.last, 'Removed apps/admin');
      expect(exists('apps/admin'), isFalse);
      expect(read('pubspec.lock'), lockBefore);
      // What the add staged leaves the index again; nothing else is reset.
      expect(
        started
            .where((process) => process.executable == git())
            .map((process) => <Object?>[process.arguments, process.workingDirectory]),
        <List<Object?>>[
          <Object?>[
            <String>['check-ignore', '-q', 'pubspec.lock'],
            root(),
          ],
          <Object?>[
            <String>['add', 'apps/admin', 'pubspec.lock'],
            root(),
          ],
          <Object?>[
            <String>['commit', '-m', 'Add Flutter app admin', '--', 'apps/admin', 'pubspec.lock'],
            root(),
          ],
          <Object?>[
            <String>['reset', '-q', '--', 'apps/admin', 'pubspec.lock'],
            root(),
          ],
        ],
      );
    });

    test('a git reset that hangs is killed and the rollback goes on', () async {
      script = (process) {
        if (process.executable != git()) return resolving(process);
        switch (process.arguments.first) {
          case 'commit':
            Timer.run(() => process.exit(128));
          case 'reset':
            // Never exits on its own.
            break;
          default:
            resolving(process);
        }
      };
      final runs = await build().addMember(member(template: NewProjectTemplate.plain)).toList();

      final reset = started.singleWhere((process) => process.arguments.first == 'reset');
      expect(reset.stopped, isTrue);
      expect(step(runs.last, CreationStepKind.commit).output.last, 'Removed apps/admin');
      expect(exists('apps/admin'), isFalse);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a failed commit with an ignored lock unstages the member alone', () async {
      lockIgnored = true;
      script = (process) {
        if (process.executable != git() || process.arguments.first != 'commit') {
          return resolving(process);
        }
        Timer.run(() => process.exit(1));
      };
      await build().addMember(member(template: NewProjectTemplate.plain)).toList();

      expect(exists('apps/admin'), isFalse);
      expect(read('pubspec.lock'), lockBefore);
      expect(
        started.where((process) => process.executable == git()).map((process) => process.arguments),
        <List<String>>[
          <String>['check-ignore', '-q', 'pubspec.lock'],
          <String>['add', 'apps/admin'],
          <String>['commit', '-m', 'Add Flutter app admin', '--', 'apps/admin'],
          <String>['reset', '-q', '--', 'apps/admin'],
        ],
      );
    });

    for (final ending in <String>['stop', 'dispose']) {
      test('$ending right after a successful commit keeps the member', () async {
        ScriptedDaemonProcess? commit;
        script = (process) {
          if (process.executable != git() || process.arguments.first != 'commit') {
            return resolving(process);
          }
          commit = process;
          // Exited with 0, the pipes still draining: the step is not marked done yet.
          Timer.run(() => process.exit(0, closePipes: false));
        };
        final repository = build();
        final runs = <CreationRun>[];
        final done = repository
            .addMember(member(template: NewProjectTemplate.plain))
            .listen(runs.add)
            .asFuture<void>();
        await until(() => commit != null);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(step(runs.last, CreationStepKind.commit).status, CreationStepStatus.running);

        if (ending == 'stop') {
          await repository.stop();
        } else {
          final disposed = repository.dispose();
          await Future<void>.delayed(Duration.zero);
          commit!.closePipes();
          await disposed;
        }
        commit!.closePipes();
        await done;

        expect(exists('apps/admin/pubspec.yaml'), isTrue);
        expect(read('pubspec.lock'), 'lock after\n');
        expect(started.map((process) => process.arguments.first), isNot(contains('reset')));
        expect(
          runs.last.steps.expand((step) => step.output),
          isNot(contains('Removed apps/admin')),
        );
      });
    }

    test('a failed analyze does not roll back', () async {
      script = (process) {
        if (process.arguments.first != 'analyze') return resolving(process);
        Timer.run(() {
          process
            ..emitLine('info • deprecated_member_use')
            ..exit(1);
        });
      };
      final runs = await build().addMember(member()).toList();

      final analyze = step(runs.last, CreationStepKind.analyze);
      expect(analyze.status, CreationStepStatus.failed);
      expect(analyze.output, <String>['info • deprecated_member_use']);
      expect(step(runs.last, CreationStepKind.commit).status, CreationStepStatus.done);
      expect(started.map((process) => process.arguments.take(2).join(' ')), contains('commit -m'));
      expect(exists('apps/admin/pubspec.yaml'), isTrue);
      expect(read('pubspec.lock'), 'lock after\n');
    });

    test('without git a failed analyze does not roll back either', () async {
      script = (process) {
        if (process.arguments.first != 'analyze') return resolving(process);
        Timer.run(() => process.exit(1));
      };
      await build().addMember(member(template: NewProjectTemplate.plain, gitRepo: false)).toList();

      expect(exists('apps/admin/pubspec.yaml'), isTrue);
      expect(read('pubspec.lock'), 'lock after\n');
    });

    test('dispose during add rolls back', () async {
      script = (process) {
        if (!isPub(process)) return resolving(process);
        File(file('pubspec.lock')).writeAsStringSync('half resolved\n');
      };
      final repository = build();
      final runs = <CreationRun>[];
      final done = repository
          .addMember(member(template: NewProjectTemplate.plain))
          .listen(runs.add)
          .asFuture<void>();
      await until(() => started.any(isPub));
      final before = runs.length;

      await repository.dispose();

      expect(started.last.stopped, isTrue);
      expect(exists('apps/admin'), isFalse);
      expect(read('pubspec.lock'), lockBefore);
      await done;
      expect(runs, hasLength(before));
    });

    test('an existing folder fails the add and is left alone', () async {
      Directory(file('apps/admin')).createSync(recursive: true);
      File(file('apps/admin/keep.txt')).writeAsStringSync('mine');
      final runs = await build().addMember(member()).toList();

      final create = step(runs.last, CreationStepKind.memberCreate);
      expect(create.status, CreationStepStatus.failed);
      expect(create.output, <String>['The folder already exists']);
      expect(started, isEmpty);
      expect(read('apps/admin/keep.txt'), 'mine');
      expect(read('pubspec.lock'), lockBefore);
    });
  });

  group('members', () {
    late String project;
    void write(String relative, String text) {
      final target = File(p.joinAll(<String>[project, ...relative.split('/')]));
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(text);
    }

    setUp(() {
      project = p.join(parent.path, 'shop');
      write('pubspec.yaml', monorepoRootPubspec(name: 'shop', sdkConstraint: '^3.14.0'));
      write('packages/core/pubspec.yaml', 'name: shop_core\n');
      write('apps/app/pubspec.yaml', 'name: shop_app\n');
    });

    test('checkMember', () async {
      final repository = build();
      expect(
        await repository.checkMember(project, MemberKind.flutterApp, 'app', 'shop_new'),
        MemberProblem.folderExists,
      );
      Directory(p.join(project, 'apps', 'empty')).createSync();
      expect(
        await repository.checkMember(project, MemberKind.dartApp, 'empty', 'shop_new'),
        MemberProblem.folderExists,
      );
      expect(
        await repository.checkMember(project, MemberKind.dartPackage, 'core2', 'shop_core'),
        MemberProblem.packageTaken,
      );
      expect(
        await repository.checkMember(project, MemberKind.dartPackage, 'root', 'shop_workspace'),
        MemberProblem.packageTaken,
      );
      // `apps/core` is free: `core` is taken under `packages/` only.
      expect(
        await repository.checkMember(project, MemberKind.flutterApp, 'core', 'shop_desk'),
        isNull,
      );
    });

    test('suggestedPackageName', () async {
      final repository = build();
      expect(await repository.suggestedPackageName(project, 'admin'), 'shop_admin');

      final cafe = p.join(parent.path, 'cafe_pos');
      Directory(cafe).createSync();
      File(p.join(cafe, 'pubspec.yaml')).writeAsStringSync('name: cafe_pos_workspace\n');
      expect(await repository.suggestedPackageName(cafe, 'admin'), 'cafe_pos_admin');

      final tools = p.join(parent.path, 'tools');
      Directory(tools).createSync();
      File(p.join(tools, 'pubspec.yaml')).writeAsStringSync('name: tools\n');
      expect(await repository.suggestedPackageName(tools, 'admin'), 'tools_admin');
    });

    test('hasUiPackage', () async {
      final repository = build();
      expect(await repository.hasUiPackage(project), isFalse);
      write('packages/ui/pubspec.yaml', 'name: ui\n');
      expect(await repository.hasUiPackage(project), isTrue);
    });

    test('isGitRepo', () async {
      final repository = build();
      expect(await repository.isGitRepo(project), isFalse);
      Directory(p.join(project, '.git')).createSync();
      expect(await repository.isGitRepo(project), isTrue);
    });

    test('scriptsListingMembers: a cafe_pos-like test.bash', () async {
      write(
        'scripts/test.bash',
        '#!/usr/bin/env bash\nset -euo pipefail\n(cd packages/core && dart test "\$@")\n',
      );
      // Mentions no folder of an existing member.
      write('scripts/analyze.bash', 'flutter analyze packages/core_utils apps/*\n');
      expect(await build().scriptsListingMembers(project), <String>['scripts/test.bash']);
    });

    test("scriptsListingMembers: the monorepo template's scripts", () async {
      for (final relative in monorepoTemplateFiles) {
        write(relative, File('$monorepoTemplateRoot$relative').readAsStringSync());
      }
      write('packages/ui/pubspec.yaml', 'name: ui\n');
      expect(await build().scriptsListingMembers(project), isEmpty);
    });

    test('scriptsListingMembers without scripts/', () async {
      expect(await build().scriptsListingMembers(project), isEmpty);
    });
  });

  group('material_ui', () {
    String dart() => p.join(p.dirname(_flutter), 'dart');

    /// The processes started, as `[executable, arguments, workingDirectory]`.
    List<List<Object?>> commands() => <List<Object?>>[
      for (final process in started)
        <Object?>[process.executable, process.arguments, process.workingDirectory],
    ];

    /// The Dart files of [files] written under [to], keyed by their template path.
    Map<String, String> written(String to, List<String> files) => <String, String>{
      for (final relative in files.where((relative) => relative.endsWith('.dart')))
        relative: File(p.joinAll(<String>[to, ...relative.split('/')])).readAsStringSync(),
    };

    /// The template's Dart files of [files], filled for [package]: copied as they are.
    Map<String, String> expected(List<String> files, String package) => <String, String>{
      for (final relative in files.where((relative) => relative.endsWith('.dart')))
        relative: fillProjectTemplate(
          File('$projectTemplateRoot$relative').readAsStringSync(),
          package: package,
          date: DateTime(2026, 11, 6),
        ),
    };

    /// The commands of a one-app architecture project without git.
    List<List<Object?>> oneApp() => <List<Object?>>[
      <Object?>[
        _flutter,
        <String>[
          'create',
          '--template',
          'app',
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
        _flutter,
        <String>['pub', 'add', ...skeletonPubAddArguments],
        path(),
      ],
      <Object?>[
        _flutter,
        <String>['pub', 'add', 'material_ui'],
        p.join(path(), 'packages', 'ui'),
      ],
      <Object?>[
        _flutter,
        <String>['pub', 'get'],
        path(),
      ],
      <Object?>[
        dart(),
        <String>['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
        path(),
      ],
      <Object?>[
        dart(),
        <String>['fix', '--apply', '--code=directives_ordering'],
        path(),
      ],
      <Object?>[
        _flutter,
        <String>['analyze'],
        path(),
      ],
    ];

    test('one app installs material_ui in the app and in ui and copies the template', () async {
      final runs = await build().create(request(gitInit: false)).toList();

      expect(runs.last.steps.map((step) => step.status), everyElement(CreationStepStatus.done));
      expect(commands(), oneApp());
      final files = written(path(), projectTemplateFiles);
      expect(files, expected(projectTemplateFiles, 'avera_booking'));
      for (final entry in files.entries) {
        expect(entry.value, isNot(contains('package:flutter/material.dart')), reason: entry.key);
      }
      expect(
        files['lib/initialization/widget/app.dart'],
        contains("import 'package:material_ui/material_ui.dart';"),
      );
      expect(
        files['packages/ui/lib/ui.dart'],
        contains("export 'package:material_ui/material_ui.dart';"),
      );
    });

    String shop() => p.join(parent.path, 'shop');

    List<List<Object?>> monorepoCommands() => <List<Object?>>[
      <Object?>[
        _flutter,
        <String>['pub', 'add', ...skeletonPubAddArgumentsFor(uiPath: '../../packages/ui')],
        p.join(shop(), 'apps', 'app'),
      ],
      <Object?>[
        _flutter,
        <String>['pub', 'add', 'material_ui'],
        p.join(shop(), 'packages', 'ui'),
      ],
      <Object?>[
        _flutter,
        <String>['pub', 'add', 'dev:build_runner'],
        shop(),
      ],
      <Object?>[
        _flutter,
        <String>['pub', 'get'],
        shop(),
      ],
      <Object?>[
        dart(),
        <String>['run', 'build_runner', 'build', '--workspace', '--delete-conflicting-outputs'],
        shop(),
      ],
      <Object?>[
        dart(),
        <String>['fix', '--apply', '--code=directives_ordering'],
        shop(),
      ],
      <Object?>[
        _flutter,
        <String>['analyze'],
        shop(),
      ],
    ];

    test('a monorepo installs material_ui in the app and in ui', () async {
      final runs = await build().create(monorepo()).toList();

      expect(runs.last.steps.map((step) => step.status), everyElement(CreationStepStatus.done));
      expect(commands().skip(1), monorepoCommands());
      expect(
        written(p.join(shop(), 'apps', 'app'), projectTemplateAppFiles),
        expected(projectTemplateAppFiles, 'shop_app'),
      );
      expect(written(shop(), projectTemplateUiFiles), expected(projectTemplateUiFiles, 'shop'));
    });

    for (final version in const <String?>['3.47.2', null]) {
      test('one app on Flutter ${version ?? 'unknown'} fails before flutter create', () async {
        flutterVersion = version;
        final runs = await build().create(request(gitInit: false)).toList();

        final create = step(runs.last, CreationStepKind.flutterCreate);
        expect(create.status, CreationStepStatus.failed);
        expect(create.output.last, 'Flutter 3.50 or newer is needed for My architecture');
        expect(started, isEmpty);
        expect(Directory(path()).existsSync(), isFalse);
      });
    }

    test('a monorepo on Flutter 3.47 fails before it writes the workspace', () async {
      flutterVersion = '3.47.2';
      final runs = await build().create(monorepo()).toList();

      final workspace = step(runs.last, CreationStepKind.workspace);
      expect(workspace.status, CreationStepStatus.failed);
      expect(workspace.output.last, 'Flutter 3.50 or newer is needed for My architecture');
      expect(started, isEmpty);
      expect(Directory(shop()).existsSync(), isFalse);
    });

    test('a plain project on Flutter 3.47 is not held back', () async {
      flutterVersion = '3.47.2';
      final runs = await build()
          .create(request(template: NewProjectTemplate.plain, gitInit: false))
          .toList();

      expect(runs.last.steps.map((step) => step.status), everyElement(CreationStepStatus.done));
    });

    group('add member', () {
      String admin() => p.join(shop(), 'apps', 'admin');

      setUp(() {
        Directory(p.join(shop(), 'packages', 'ui')).createSync(recursive: true);
        File(p.join(shop(), 'pubspec.yaml')).writeAsStringSync(
          '${monorepoRootPubspec(name: 'shop', sdkConstraint: '^3.14.0')}'
          '\ndev_dependencies:\n  build_runner: ^2.11.0\n',
        );
        File(p.join(shop(), 'packages', 'ui', 'pubspec.yaml')).writeAsStringSync('name: ui\n');
      });

      NewMemberRequest member({NewProjectTemplate template = NewProjectTemplate.architecture}) =>
          NewMemberRequest(
            projectId: 1,
            projectPath: shop(),
            kind: MemberKind.flutterApp,
            folder: 'admin',
            packageName: 'shop_admin',
            org: 'com.example',
            platforms: const <FlutterPlatform>{FlutterPlatform.macos},
            template: template,
            gitRepo: false,
          );

      /// The commands after `flutter create`; the user's `packages/ui` is never touched.
      List<List<Object?>> memberCommands() => <List<Object?>>[
        <Object?>[
          _flutter,
          <String>['pub', 'add', ...skeletonPubAddArgumentsFor(uiPath: '../../packages/ui')],
          admin(),
        ],
        <Object?>[
          _flutter,
          <String>['pub', 'get'],
          shop(),
        ],
        <Object?>[
          dart(),
          <String>['run', 'build_runner', 'build', '--workspace', '--delete-conflicting-outputs'],
          shop(),
        ],
        <Object?>[
          dart(),
          <String>['fix', '--apply', '--code=directives_ordering'],
          admin(),
        ],
        <Object?>[
          _flutter,
          <String>['analyze'],
          admin(),
        ],
      ];

      test('an added app gets material_ui and leaves packages/ui alone', () async {
        final runs = await build().addMember(member()).toList();

        expect(runs.last.steps.map((step) => step.status), everyElement(CreationStepStatus.done));
        expect(commands().skip(1), memberCommands());
        expect(
          written(admin(), projectTemplateAppFiles),
          expected(projectTemplateAppFiles, 'shop_admin'),
        );
        expect(
          File(p.join(shop(), 'packages', 'ui', 'pubspec.yaml')).readAsStringSync(),
          'name: ui\n',
        );
      });

      test('an app added on Flutter 3.47 fails before flutter create', () async {
        flutterVersion = '3.47.2';
        final runs = await build().addMember(member()).toList();

        final create = step(runs.last, CreationStepKind.memberCreate);
        expect(create.status, CreationStepStatus.failed);
        expect(create.output.last, 'Flutter 3.50 or newer is needed for My architecture');
        expect(started, isEmpty);
        expect(Directory(admin()).existsSync(), isFalse);
        expect(Directory(p.join(shop(), 'packages', 'ui')).existsSync(), isTrue);
      });

      test('an empty app added on Flutter 3.47 is not held back', () async {
        flutterVersion = '3.47.2';
        final runs = await build().addMember(member(template: NewProjectTemplate.plain)).toList();

        expect(runs.last.steps.map((step) => step.status), everyElement(CreationStepStatus.done));
      });
    });
  });
}
