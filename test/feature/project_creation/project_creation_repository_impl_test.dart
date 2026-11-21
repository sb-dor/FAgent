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
      expect(read('packages/ui/pubspec.yaml'), contains('sdk: ^3.14.0'));
      expect(read('packages/ui/pubspec.yaml'), contains('shaders/shimmer.frag'));
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

    test('a Dart member is renamed and its imports follow', () async {
      script = (process) {
        if (process.executable == p.join(p.dirname(_flutter), 'dart') &&
            process.arguments.first == 'create') {
          final dir = process.arguments.last;
          Directory(p.join(dir, 'bin')).createSync(recursive: true);
          Directory(p.join(dir, '.dart_tool')).createSync(recursive: true);
          File(p.join(dir, 'pubspec.yaml')).writeAsStringSync(
            'name: server\n\nenvironment:\n  sdk: ^3.10.4\n\ndependencies:\n  path: ^1.0.0\n',
          );
          File(p.join(dir, 'bin', 'server.dart'))
              .writeAsStringSync("import 'package:server/server.dart';\n");
          File(p.join(dir, '.dart_tool', 'x.dart'))
              .writeAsStringSync("import 'package:server/server.dart';\n");
          File(p.join(dir, 'analysis_options.yaml'))
              .writeAsStringSync('include: package:lints/recommended.yaml\n');
        }
        finish(process);
      };
      Directory(root()).createSync();
      final request = monorepo(template: NewProjectTemplate.plain);
      final member = p.join(root(), 'apps', 'server');

      await build().createMemberForTest(
        request,
        kind: MemberKind.dartApp,
        path: member,
        packageName: 'shop_server',
        sdkConstraint: '^3.14.0',
      );

      expect(started.single.arguments, <String>['create', '-t', 'console', '--no-pub', member]);
      expect(started.single.workingDirectory, root());
      final pubspec = read('apps/server/pubspec.yaml');
      expect(pubspec, startsWith('name: shop_server\n'));
      expect(pubspec, contains('sdk: ^3.14.0\n\nresolution: workspace\n'));
      expect(read('apps/server/bin/server.dart'), "import 'package:shop_server/server.dart';\n");
      expect(read('apps/server/.dart_tool/x.dart'), contains('package:server/'));
      expect(read('apps/server/analysis_options.yaml'), 'include: ../../analysis_options.yaml\n');
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
}
