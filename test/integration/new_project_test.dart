@Tags(<String>['flutter'])
library;

import 'dart:io' as io;

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_code_agent/src/feature/project_opening/data/project_opening_repository.dart';
import 'package:flutter_code_agent/src/feature/project_rules/data/project_rules_repository.dart';
import 'package:flutter_code_agent/src/feature/project_rules/models/project_rule.dart';
import 'package:flutter_code_agent/src/feature/project_trust/data/project_trust_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Creates a project from the "My architecture" template with the real `flutter` (no git) in a
/// temp folder, then runs `flutter test` in it: the gate for the skeleton in
/// `assets/project_template/architecture/` (the creation itself runs `flutter analyze`).
///
/// Opt-in, needs the network:
/// `FLUTTER_RUN_TEST=1 flutter test --tags flutter test/integration/new_project_test.dart`.
void main() {
  final enabled = io.Platform.environment['FLUTTER_RUN_TEST'] == '1';

  test(
    'the architecture template creates a project that passes analyze and test',
    () async {
      final environment = ShellEnvironment(Map<String, String>.of(io.Platform.environment));
      final root = io.Directory.systemTemp.createTempSync('new_project_test');
      addTearDown(() => root.deleteSync(recursive: true));
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final sdk = FlutterSdkRepositoryImpl(
        which: environment.which,
        environment: environment.variables,
      );
      final flutter = (await sdk.sdkFor(null)).path;
      expect(flutter, isNotNull, reason: 'flutter is not on the PATH');

      final repository = ProjectCreationRepositoryImpl(
        database: database,
        flutterSdk: sdk,
        environment: environment,
        projectOpening: ProjectOpeningRepositoryImpl(database: database),
        projectTrust: ProjectTrustRepositoryImpl(database: database),
        projectRules: _NoRules(),
        loadAsset: (key) => io.File(key).readAsString(),
      );
      addTearDown(repository.dispose);
      final request = NewProjectRequest(
        name: 'skeleton_probe',
        org: 'com.example',
        parent: root.path,
        platforms: const <FlutterPlatform>{FlutterPlatform.macos},
        gitInit: false,
      );

      final runs = await repository.create(request).toList();

      final last = runs.last;
      String report() => <String>[
        for (final step in last.steps) ...<String>[
          '${step.kind.name}: ${step.status.name}',
          ...step.output.map((line) => '  $line'),
        ],
      ].join('\n');
      expect(last.steps.map((step) => step.kind), <CreationStepKind>[
        CreationStepKind.flutterCreate,
        CreationStepKind.skeleton,
        CreationStepKind.analyze,
      ]);
      expect(
        last.steps.map((step) => step.status),
        everyElement(CreationStepStatus.done),
        reason: report(),
      );
      expect(last.projectId, isNotNull);
      // ignore: avoid_print
      print(report());

      final tested = await io.Process.run(
        flutter!,
        const <String>['test'],
        workingDirectory: p.join(root.path, 'skeleton_probe'),
        environment: environment.variables,
      );
      expect(tested.exitCode, 0, reason: '${tested.stdout}\n${tested.stderr}');
    },
    skip: enabled ? false : 'set FLUTTER_RUN_TEST=1 to run (needs the network)',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// No built-in rules: the skeleton is what this test checks.
final class _NoRules implements IProjectRulesRepository {
  @override
  Future<bool> hasRules(String projectRoot) async => false;

  @override
  Future<List<ProjectRule>> builtinRules() async => const <ProjectRule>[];

  @override
  Future<void> write(String projectRoot, List<ProjectRule> rules) async {}

  @override
  Future<void> markOffered(int projectId) async {}
}
