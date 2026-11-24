@Tags(<String>['flutter'])
library;

import 'dart:io' as io;

import 'package:drift/native.dart';
import 'package:flutter_code_agent/_core/database/database.dart';
import 'package:flutter_code_agent/_core/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/flutter_sdk/data/flutter_sdk_repository_impl.dart';
import 'package:flutter_code_agent/project_creation/data/project_creation_repository_impl.dart';
import 'package:flutter_code_agent/project_creation/data/project_template.dart';
import 'package:flutter_code_agent/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/project_creation/models/new_member_request.dart';
import 'package:flutter_code_agent/project_creation/models/new_project_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Creates a project from the "My architecture" template with the real `flutter` (no git) in a
/// temp folder, then runs `flutter test` in it (the copied tests of the telemetry module included)
/// and builds it for the web: the gate for the skeleton in `assets/project_template/architecture/` and the module in
/// `lib/_core/telemetry/` (the creation itself runs `flutter analyze`). Then
/// creates a monorepo (`packages/ui` and the shared `telemetry`, `database` and `api_client`), adds
/// a member of every kind to it and runs `make analyze`, `make test` (the module's tests in
/// `packages/telemetry/test/` included), a macOS and a web build in it: the gate for
/// `assets/project_template/monorepo/` and "Add to project".
/// Last, one app with Crashlytics (no `flutterfire configure`) and one with the log only: the
/// gate for the other crash reporters.
///
/// Opt-in, needs the network:
/// `FLUTTER_RUN_TEST=1 flutter test --tags flutter test/integration/new_project_test.dart`.
void main() {
  final enabled = io.Platform.environment['FLUTTER_RUN_TEST'] == '1';

  /// A repository on the real `flutter` of the PATH, released when the test ends, and that
  /// `flutter`.
  Future<(ProjectCreationRepositoryImpl, String, ShellEnvironment)> realRepository() async {
    final environment = ShellEnvironment(Map<String, String>.of(io.Platform.environment));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final sdk = FlutterSdkRepositoryImpl(
      which: environment.which,
      environment: environment.variables,
    );
    final found = await sdk.sdkFor(null);
    final flutter = found.path;
    expect(flutter, isNotNull, reason: 'flutter is not on the PATH');

    final repository = ProjectCreationRepositoryImpl(
      database: database,
      flutter: () async => flutter,
      environment: environment,
      // No built-in rules: the skeleton is what this test checks.
      writeRules: (_) async => const <String>[],
      loadAsset: (key) => io.File(key).readAsString(),
      dartVersion: () async => found.dartVersion,
      flutterVersion: () async => found.version,
    );
    addTearDown(repository.dispose);
    return (repository, flutter!, environment);
  }

  /// The steps of [run] with their output, for a failure's reason.
  String report(CreationRun run) => <String>[
    for (final step in run.steps) ...<String>[
      '${step.kind.name}: ${step.status.name}',
      ...step.output.map((line) => '  $line'),
    ],
  ].join('\n');

  /// Expects every step of [run] done, `analyze` included: the skeleton imports `material_ui` and
  /// `cupertino_ui`, so it reports nothing on the Flutter 3.50 or newer it needs.
  void expectFinished(CreationRun run, {String? what}) {
    final reason = '${what == null ? '' : '$what\n'}${report(run)}';
    for (final step in run.steps) {
      expect(step.status, CreationStepStatus.done, reason: '${step.kind.name}\n$reason');
    }
  }

  test(
    'the architecture template creates a project that passes analyze and test',
    () async {
      final (repository, flutter, environment) = await realRepository();
      final root = io.Directory.systemTemp.createTempSync('new_project_test');
      addTearDown(() => root.deleteSync(recursive: true));
      final request = NewProjectRequest(
        name: 'skeleton_probe',
        org: 'com.example',
        parent: root.path,
        platforms: const <FlutterPlatform>{FlutterPlatform.macos, FlutterPlatform.web},
        gitInit: false,
      );

      final runs = await repository.create(request).toList();

      final last = runs.last;
      expect(last.steps.map((step) => step.kind), <CreationStepKind>[
        CreationStepKind.flutterCreate,
        CreationStepKind.skeleton,
        CreationStepKind.analyze,
        CreationStepKind.rules,
      ]);
      expectFinished(last);
      // ignore: avoid_print
      print(report(last));

      // The tests of the telemetry module came with it, and run with the project's own.
      final moduleTests = io.Directory(
        p.join(root.path, 'skeleton_probe', 'test', '_core', 'telemetry'),
      );
      expect(moduleTests.existsSync(), isTrue);
      expect(
        moduleTests.listSync().whereType<io.File>(),
        hasLength(telemetryModuleTestFiles.length),
      );

      final tested = await io.Process.run(
        flutter,
        const <String>['test'],
        workingDirectory: p.join(root.path, 'skeleton_probe'),
        environment: environment.variables,
      );
      expect(tested.exitCode, 0, reason: '${tested.stdout}\n${tested.stderr}');
      expect(tested.stdout, contains('test/_core/telemetry/'));

      // The asset bundle compiles the shader of packages/ui: a wrong path in pubspec.yaml fails
      // here, not in `analyze` or `test`.
      final bundled = await io.Process.run(
        flutter,
        const <String>['build', 'bundle'],
        workingDirectory: p.join(root.path, 'skeleton_probe'),
        environment: environment.variables,
      );
      expect(bundled.exitCode, 0, reason: '${bundled.stdout}\n${bundled.stderr}');

      // The web build takes the console-only `ErrorUtil`: the module (drift, `dart:io`) stays out.
      final web = await io.Process.run(
        flutter,
        const <String>['build', 'web'],
        workingDirectory: p.join(root.path, 'skeleton_probe'),
        environment: environment.variables,
      );
      expect(web.exitCode, 0, reason: '${web.stdout}\n${web.stderr}');
    },
    skip: enabled ? false : 'set FLUTTER_RUN_TEST=1 to run (needs the network)',
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'a typed application ID reaches every platform and the macOS and Android builds',
    () async {
      final (repository, flutter, environment) = await realRepository();
      final root = io.Directory.systemTemp.createTempSync('new_project_test');
      addTearDown(() => root.deleteSync(recursive: true));
      final app = p.join(root.path, 'id_probe');
      final request = NewProjectRequest(
        name: 'id_probe',
        org: 'tj.avera',
        applicationId: 'tj.avera.pos_app',
        parent: root.path,
        platforms: FlutterPlatform.values.toSet(),
        template: NewProjectTemplate.plain,
        gitInit: false,
      );

      final last = (await repository.create(request).toList()).last;
      expectFinished(last);
      String read(String relative) => io.File(p.join(app, relative)).readAsStringSync();

      expect(read('android/app/build.gradle.kts'), contains('applicationId = "tj.avera.pos_app"'));
      expect(read('android/app/build.gradle.kts'), contains('namespace = "tj.avera.pos_app"'));
      expect(
        read('android/app/src/main/kotlin/tj/avera/pos_app/MainActivity.kt'),
        startsWith('package tj.avera.pos_app'),
      );
      expect(read('linux/CMakeLists.txt'), contains('APPLICATION_ID "tj.avera.pos_app"'));
      for (final file in const <String>[
        'ios/Runner.xcodeproj/project.pbxproj',
        'macos/Runner.xcodeproj/project.pbxproj',
        'macos/Runner/Configs/AppInfo.xcconfig',
      ]) {
        final text = read(file);
        expect(text, contains('PRODUCT_BUNDLE_IDENTIFIER = tj.avera.posApp'), reason: file);
        expect(text, isNot(contains('idProbe')), reason: file);
      }

      final macos = await io.Process.run(
        flutter,
        const <String>['build', 'macos', '--debug'],
        workingDirectory: app,
        environment: environment.variables,
      );
      expect(macos.exitCode, 0, reason: '${macos.stdout}\n${macos.stderr}');
      final plist = io.File(
        p.join(app, 'build/macos/Build/Products/Debug/id_probe.app/Contents/Info.plist'),
      ).readAsStringSync();
      expect(plist, contains('<string>tj.avera.posApp</string>'));

      final apk = await io.Process.run(
        flutter,
        const <String>['build', 'apk', '--debug'],
        workingDirectory: app,
        environment: environment.variables,
      );
      expect(apk.exitCode, 0, reason: '${apk.stdout}\n${apk.stderr}');
    },
    skip: enabled ? false : 'set FLUTTER_RUN_TEST=1 to run (needs the network)',
    timeout: const Timeout(Duration(minutes: 20)),
  );

  for (final reporter in const <CrashReporter>[CrashReporter.crashlytics, CrashReporter.logOnly]) {
    test(
      'one app with ${reporter.name} passes analyze and test',
      () async {
        final (repository, flutter, environment) = await realRepository();
        final root = io.Directory.systemTemp.createTempSync('new_project_${reporter.name}_test');
        addTearDown(() => root.deleteSync(recursive: true));
        final request = NewProjectRequest(
          name: 'reporter_probe',
          org: 'com.example',
          parent: root.path,
          platforms: const <FlutterPlatform>{FlutterPlatform.macos},
          gitInit: false,
          crashReporter: reporter,
        );

        final last = (await repository.create(request).toList()).last;
        // The analyze step passed: without `flutterfire configure` too.
        expectFinished(last, what: reporter.name);
        expect(
          last.notes,
          reporter == CrashReporter.crashlytics
              ? <CreationNote>[CreationNote.flutterfireConfigure]
              : isEmpty,
        );

        final project = p.join(root.path, 'reporter_probe');
        final pubspec = io.File(p.join(project, 'pubspec.yaml')).readAsStringSync();
        if (reporter == CrashReporter.crashlytics) {
          expect(pubspec, allOf(contains('firebase_core:'), contains('firebase_crashlytics:')));
          expect(pubspec, contains('sentry:'));
        } else {
          expect(pubspec, isNot(contains('sentry')));
          expect(pubspec, isNot(contains('firebase')));
        }

        final tested = await io.Process.run(
          flutter,
          const <String>['test'],
          workingDirectory: project,
          environment: environment.variables,
        );
        expect(tested.exitCode, 0, reason: '${tested.stdout}\n${tested.stderr}');
        expect(tested.stdout, contains('test/_core/telemetry/'));
        if (reporter == CrashReporter.crashlytics) {
          // The reporter's own test: no gateway and one log line while Firebase is not set up.
          final own = await io.Process.run(
            flutter,
            const <String>['test', 'test/_core/telemetry/crash_reporter_test.dart'],
            workingDirectory: project,
            environment: environment.variables,
          );
          expect(own.exitCode, 0, reason: '${own.stdout}\n${own.stderr}');
          expect(own.stdout, contains('+5: All tests passed!'));
        }
      },
      skip: enabled ? false : 'set FLUTTER_RUN_TEST=1 to run (needs the network)',
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }

  test(
    'monorepo with every kind of member',
    () async {
      final (repository, flutter, environment) = await realRepository();
      final parent = io.Directory.systemTemp.createTempSync('new_monorepo_test');
      addTearDown(() => parent.deleteSync(recursive: true));
      final request = NewProjectRequest(
        name: 'shop',
        org: 'com.example',
        parent: parent.path,
        platforms: const <FlutterPlatform>{FlutterPlatform.macos, FlutterPlatform.web},
        gitInit: false,
        structure: ProjectStructure.monorepo,
      );

      final created = (await repository.create(request).toList()).last;
      expectFinished(created);
      // The app keeps its glue; the module, the database and the HTTP client are packages.
      for (final name in <String>['ui', ...monorepoSharedPackages]) {
        expect(
          io.File(p.join(request.path, 'packages', name, 'pubspec.yaml')).existsSync(),
          isTrue,
          reason: name,
        );
      }
      expect(
        io.Directory(p.join(request.path, 'apps', 'app', 'lib', '_core', 'api_client'))
            .existsSync(),
        isFalse,
      );
      final moduleTests = io.Directory(p.join(request.path, 'packages', 'telemetry', 'test'));
      expect(
        moduleTests.listSync().whereType<io.File>(),
        hasLength(telemetryModuleTestFiles.length),
      );

      for (final (kind, folder) in const <(MemberKind, String)>[
        (MemberKind.flutterApp, 'admin'),
        (MemberKind.dartApp, 'server'),
        (MemberKind.flutterPackage, 'kit'),
        (MemberKind.dartPackage, 'core'),
      ]) {
        final added =
            (await repository
                    .addMember(
                      NewMemberRequest(
                        projectId: 1,
                        projectPath: request.path,
                        kind: kind,
                        folder: folder,
                        packageName: await repository.suggestedPackageName(request.path, folder),
                        org: 'com.example',
                        platforms: const <FlutterPlatform>{FlutterPlatform.macos},
                        template: NewProjectTemplate.architecture,
                        gitRepo: false,
                      ),
                    )
                    .toList())
                .last;
        expectFinished(added, what: '${kind.name} $folder');
      }

      Future<String> run(String executable, List<String> arguments, {String? inFolder}) async {
        final result = await io.Process.run(
          executable,
          arguments,
          workingDirectory: inFolder ?? request.path,
          environment: environment.variables,
        );
        expect(
          result.exitCode,
          0,
          reason: '$executable ${arguments.join(' ')}\n${result.stdout}\n${result.stderr}',
        );
        return '${result.stdout}';
      }

      // The workspace's own scripts find the three packages.
      await run('make', const <String>['analyze']);
      final tested = await run('make', const <String>['test']);
      expect(tested, contains('==> packages/telemetry/'));
      expect(tested, contains('==> apps/admin/'));
      expect(tested, isNot(contains('Some tests failed')));
      // The module's tests ran in their package: the JSON report of scripts/test.bash names each.
      final report = io.File(p.join(request.path, 'packages', 'telemetry', 'reports', 'tests.json'))
          .readAsStringSync();
      for (final file in telemetryModuleTestFiles) {
        expect(report, contains('packages/telemetry/test/$file'), reason: file);
      }
      // The macOS build compiles the shimmer shader the app takes from packages/ui.
      await run(flutter, const <String>[
        'build',
        'macos',
        '--debug',
      ], inFolder: p.join(request.path, 'apps', 'app'));
      // The web build of the app: `packages/telemetry` is reached through the conditional import
      // only, so drift and `dart:io` stay out of it.
      await run(flutter, const <String>[
        'build',
        'web',
      ], inFolder: p.join(request.path, 'apps', 'app'));
    },
    skip: enabled ? false : 'set FLUTTER_RUN_TEST=1 to run (needs the network)',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
