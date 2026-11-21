@Tags(<String>['flutter'])
library;

import 'dart:io' as io;

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_member_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Creates a project from the "My architecture" template with the real `flutter` (no git) in a
/// temp folder, then runs `flutter test` in it: the gate for the skeleton in
/// `assets/project_template/architecture/` (the creation itself runs `flutter analyze`). Then
/// creates a monorepo, adds a member of every kind to it and runs its scripts, `flutter analyze`
/// and a macOS build in it: the gate for `assets/project_template/monorepo/` and "Add to project".
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

  /// Expects every step of [run] done. On a Flutter whose `material.dart` is deprecated (3.47 and
  /// newer) the skeleton's imports of it are infos that fail `flutter analyze`: an `analyze` that
  /// reports nothing else passes, and the steps after it stay pending.
  void expectFinished(CreationRun run, {String? what}) {
    final reason = '${what == null ? '' : '$what\n'}${report(run)}';
    final analyze = run.steps.indexWhere((step) => step.kind == CreationStepKind.analyze);
    final issues = analyze < 0
        ? const <String>[]
        : run.steps[analyze].output.where((line) => line.contains(' • ')).toList();
    final failedOnDeprecations =
        analyze >= 0 &&
        run.steps[analyze].status == CreationStepStatus.failed &&
        issues.isNotEmpty &&
        issues.every((line) => line.trimRight().endsWith('• deprecated_member_use'));
    for (final (index, step) in run.steps.indexed) {
      final expected = !failedOnDeprecations || index < analyze
          ? CreationStepStatus.done
          : index == analyze
          ? CreationStepStatus.failed
          : CreationStepStatus.pending;
      expect(step.status, expected, reason: '${step.kind.name}\n$reason');
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
        platforms: const <FlutterPlatform>{FlutterPlatform.macos},
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

      final tested = await io.Process.run(
        flutter,
        const <String>['test'],
        workingDirectory: p.join(root.path, 'skeleton_probe'),
        environment: environment.variables,
      );
      expect(tested.exitCode, 0, reason: '${tested.stdout}\n${tested.stderr}');

      // The asset bundle compiles the shader of packages/ui: a wrong path in pubspec.yaml fails
      // here, not in `analyze` or `test`.
      final bundled = await io.Process.run(
        flutter,
        const <String>['build', 'bundle'],
        workingDirectory: p.join(root.path, 'skeleton_probe'),
        environment: environment.variables,
      );
      expect(bundled.exitCode, 0, reason: '${bundled.stdout}\n${bundled.stderr}');
    },
    skip: enabled ? false : 'set FLUTTER_RUN_TEST=1 to run (needs the network)',
    timeout: const Timeout(Duration(minutes: 10)),
  );

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
        platforms: const <FlutterPlatform>{FlutterPlatform.macos},
        gitInit: false,
        structure: ProjectStructure.monorepo,
      );

      final created = (await repository.create(request).toList()).last;
      expectFinished(created);

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

      Future<void> run(String executable, List<String> arguments, {String? inFolder}) async {
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
      }

      await run('bash', const <String>['scripts/test.bash']);
      // Infos are allowed: the skeleton's `material.dart` imports are deprecated on newer Flutter.
      await run(flutter, const <String>['analyze', '--no-fatal-infos']);
      // The macOS build compiles the shimmer shader the app takes from packages/ui.
      await run(flutter, const <String>[
        'build',
        'macos',
        '--debug',
      ], inFolder: p.join(request.path, 'apps', 'app'));
    },
    skip: enabled ? false : 'set FLUTTER_RUN_TEST=1 to run (needs the network)',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
