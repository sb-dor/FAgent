import 'dart:io';

import 'package:flutter_code_agent/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/project_creation/controller/project_creation_controller.dart';
import 'package:flutter_code_agent/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/project_creation/models/new_member_request.dart';
import 'package:flutter_code_agent/project_creation/models/new_project_request.dart';
import 'package:flutter_code_agent/project_opening/data/project_opening_repository.dart';
import 'package:flutter_code_agent/project_rules/data/project_rules_repository.dart';
import 'package:flutter_code_agent/project_rules/models/project_rule.dart';
import 'package:flutter_code_agent/project_trust/data/project_trust_repository.dart';
import 'package:flutter_code_agent/projects/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_project_creation_repository.dart';

const _request = NewProjectRequest(
  name: 'avera_booking',
  org: 'com.example',
  parent: '/Users/test/StudioProjects',
);

const _member = NewMemberRequest(
  projectId: 3,
  projectPath: '/Users/test/StudioProjects/shop',
  kind: MemberKind.flutterApp,
  folder: 'admin',
  packageName: 'shop_admin',
  org: 'com.example',
  platforms: <FlutterPlatform>{},
  template: NewProjectTemplate.architecture,
  gitRepo: true,
);

Future<void> _until(ProjectCreationController controller, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  late MemoryProjectCreationRepository repository;
  late List<String> calls;
  late _Opening opening;
  late ProjectCreationController controller;

  /// A controller on [repository] whose opening, trust and rules calls go into [calls].
  ProjectCreationController build(IProjectCreationRepository repository) =>
      ProjectCreationController(
        repository: repository,
        projectOpening: opening,
        projectTrust: _Trust(calls),
        projectRules: _Rules(calls),
      );

  setUp(() {
    repository = MemoryProjectCreationRepository();
    calls = <String>[];
    opening = _Opening(calls);
    controller = build(repository);
  });

  tearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });

  test('starts idle and wraps the repository checks', () async {
    expect(controller.state, isA<ProjectCreation$IdleState>());
    expect(await controller.defaultParent(), '/Users/test/StudioProjects');
    expect(await controller.checkTarget('/Users/test/StudioProjects', 'x'), isNull);
  });

  test('runs a creation to completed with every step done', () async {
    controller.start(_request);
    expect(controller.state, isA<ProjectCreation$RunningState>());

    await _until(controller, () => controller.state is ProjectCreation$CompletedState);

    final state = controller.state as ProjectCreation$CompletedState;
    expect(state.request, _request);
    expect(state.steps.map((s) => s.kind), creationStepsFor(_request));
    expect(state.steps.every((s) => s.status == CreationStepStatus.done), isTrue);
  });

  test('completed carries the notes of the run', () async {
    controller.start(_request.copyWith(crashReporter: CrashReporter.crashlytics));
    await _until(controller, () => controller.state is ProjectCreation$CompletedState);

    final state = controller.state as ProjectCreation$CompletedState;
    expect(state.creationNotes, <CreationNote>[CreationNote.flutterfireConfigure]);
    expect(state.notes, isEmpty);
  });

  test('a Sentry project completes without notes', () async {
    controller.start(_request);
    await _until(controller, () => controller.state is ProjectCreation$CompletedState);

    expect((controller.state as ProjectCreation$CompletedState).creationNotes, isEmpty);
  });

  test('ignores a start while one is running or finished', () async {
    controller
      ..start(_request)
      ..start(_request.copyWith(name: 'other'));
    await _until(controller, () => controller.state is ProjectCreation$CompletedState);
    controller.start(_request.copyWith(name: 'third'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repository.requests.map((r) => r.name), <String>['avera_booking']);
  });

  test('reset goes from completed back to idle and allows a new start', () async {
    controller.start(_request);
    await _until(controller, () => controller.state is ProjectCreation$CompletedState);

    controller.reset();
    expect(controller.state, isA<ProjectCreation$IdleState>());

    controller.start(_request.copyWith(name: 'second'));
    await _until(controller, () => controller.state is ProjectCreation$CompletedState);
    expect(repository.requests.map((r) => r.name), <String>['avera_booking', 'second']);
  });

  test('reset does nothing while running', () async {
    controller
      ..start(_request)
      ..reset();

    expect(controller.state, isA<ProjectCreation$RunningState>());
    await _until(controller, () => controller.state is ProjectCreation$CompletedState);
  });

  test('a failing stream ends in failed with the steps it had', () async {
    final failing = build(_FailingRepository());
    addTearDown(failing.dispose);

    failing.start(_request);
    await _until(failing, () => failing.state is ProjectCreation$FailedState);

    final state = failing.state as ProjectCreation$FailedState;
    expect(state.error, isA<StateError>());
    expect(state.steps.first.status, CreationStepStatus.running);
    failing.reset();
    expect(failing.state, isA<ProjectCreation$IdleState>());
  });

  test('a stream that ends with a failed step ends in failed, not completed', () async {
    final failing = build(_FailedStepRepository());
    addTearDown(failing.dispose);

    failing.start(_request);
    await _until(failing, () => failing.state is! ProjectCreation$RunningState);

    final state = failing.state as ProjectCreation$FailedState;
    expect(state.error, isA<CreationStepFailed>());
    expect((state.error as CreationStepFailed).kind, CreationStepKind.flutterCreate);
    expect(state.steps.first.status, CreationStepStatus.failed);
    expect(state.steps.last.status, CreationStepStatus.pending);
  });

  test('the failure names the step that failed', () async {
    final failing = build(_FailedStepRepository(failAt: 1));
    addTearDown(failing.dispose);

    failing.start(_request);
    await _until(failing, () => failing.state is! ProjectCreation$RunningState);

    final state = failing.state as ProjectCreation$FailedState;
    expect((state.error as CreationStepFailed).kind, creationStepsFor(_request)[1]);
  });

  test(
    'a finished creation opens, trusts and marks the project, then completes with its id',
    () async {
      opening.projectId = 7;

      controller.start(_request);
      await _until(controller, () => controller.state is ProjectCreation$CompletedState);

      expect(calls, <String>['open ${_request.path}', 'trust 7', 'markOffered 7']);
      expect((controller.state as ProjectCreation$CompletedState).projectId, 7);
    },
  );

  test('a later step that failed still opens the project; failed carries its id', () async {
    opening.projectId = 7;
    final failing = build(MemoryProjectCreationRepository()..failAt = CreationStepKind.analyze);
    addTearDown(failing.dispose);

    failing.start(_request);
    await _until(failing, () => failing.state is! ProjectCreation$RunningState);

    final state = failing.state as ProjectCreation$FailedState;
    expect(calls, <String>['open ${_request.path}', 'trust 7', 'markOffered 7']);
    expect(state.projectId, 7);
    expect((state.error as CreationStepFailed).kind, CreationStepKind.analyze);
  });

  test('a failed flutter create opens nothing', () async {
    final failing = build(_FailedStepRepository());
    addTearDown(failing.dispose);

    failing.start(_request);
    await _until(failing, () => failing.state is! ProjectCreation$RunningState);

    expect(calls, isEmpty);
    expect((failing.state as ProjectCreation$FailedState).projectId, isNull);
  });

  test('a failure to open the project is the failed state, without an id', () async {
    opening.error = const FileSystemException('Folder does not exist');
    final failing = build(MemoryProjectCreationRepository());
    addTearDown(failing.dispose);

    failing.start(_request);
    await _until(failing, () => failing.state is! ProjectCreation$RunningState);

    final state = failing.state as ProjectCreation$FailedState;
    expect(state.error, isA<FileSystemException>());
    expect(state.projectId, isNull);
    expect(state.steps.every((step) => step.status == CreationStepStatus.done), isTrue);
    expect(calls, <String>['open ${_request.path}']);
  });

  test('a cancelled creation opens nothing', () async {
    final slow = MemoryProjectCreationRepository(step: const Duration(milliseconds: 5));
    final cancelled = build(slow)..start(_request);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(
      (cancelled.state as ProjectCreation$RunningState).steps.first.status,
      CreationStepStatus.done,
    );

    cancelled.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(calls, isEmpty);
  });

  test('stop asks the repository while running, and only then', () async {
    controller.stop();
    expect(repository.stopCalls, 0);

    controller
      ..start(_request)
      ..stop();
    expect(repository.stopCalls, 1);
    await _until(controller, () => controller.state is ProjectCreation$CompletedState);

    controller.stop();
    expect(repository.stopCalls, 1);
  });

  test('stop twice asks the repository once', () async {
    controller
      ..start(_request)
      ..stop()
      ..stop();

    expect(repository.stopCalls, 1);
    expect((controller.state as ProjectCreation$RunningState).stopping, isTrue);
    await _until(controller, () => controller.state is! ProjectCreation$RunningState);
  });

  test('stopping survives later snapshots', () async {
    final slow = MemoryProjectCreationRepository(step: const Duration(milliseconds: 5));
    final stopping = build(slow);
    addTearDown(stopping.dispose);

    stopping.start(_request);
    await Future<void>.delayed(const Duration(milliseconds: 12));
    final before = (stopping.state as ProjectCreation$RunningState).steps;
    stopping.stop();
    await Future<void>.delayed(const Duration(milliseconds: 25));

    final state = stopping.state as ProjectCreation$RunningState;
    expect(state.stopping, isTrue);
    expect(state.steps, isNot(before));
    await _until(stopping, () => stopping.state is! ProjectCreation$RunningState);
  });

  test('a run that ends with a running step is failed, not completed', () async {
    final interrupted = build(_InterruptedRepository());
    addTearDown(interrupted.dispose);

    interrupted.start(_request);
    await _until(interrupted, () => interrupted.state is! ProjectCreation$RunningState);

    final state = interrupted.state as ProjectCreation$FailedState;
    expect(state.error, isA<CreationInterrupted>());
    expect('${state.error}', 'CreationInterrupted');
    // The repository was disposed: nothing is opened.
    expect(state.projectId, isNull);
    expect(calls, isEmpty);
    expect(state.steps.first.status, CreationStepStatus.done);
    expect(state.steps[1].status, CreationStepStatus.running);
  });

  test('startAdd completes without adding a project', () async {
    controller.startAdd(_member);
    expect(controller.state, isA<ProjectCreation$RunningState>());

    await _until(controller, () => controller.state is ProjectCreation$CompletedState);

    final state = controller.state as ProjectCreation$CompletedState;
    expect(state.member, _member);
    expect(state.request, isNull);
    expect(state.projectId, isNull);
    expect(state.steps.map((s) => s.kind), memberStepsFor(_member));
    expect(state.steps.every((s) => s.status == CreationStepStatus.done), isTrue);
    expect(repository.memberRequests, <NewMemberRequest>[_member]);
    expect(calls, isEmpty);
  });

  test('startAdd failure is Failed with the step', () async {
    final failing = build(MemoryProjectCreationRepository()..failAt = CreationStepKind.analyze);
    addTearDown(failing.dispose);

    failing.startAdd(_member);
    await _until(failing, () => failing.state is! ProjectCreation$RunningState);

    final state = failing.state as ProjectCreation$FailedState;
    expect((state.error as CreationStepFailed).kind, CreationStepKind.analyze);
    expect(state.member, _member);
    expect(calls, isEmpty);
  });

  test('notes name the scripts that list members', () async {
    repository.listingScripts = <String>['scripts/get.sh', 'Makefile'];

    controller.startAdd(_member);
    await _until(controller, () => controller.state is ProjectCreation$CompletedState);

    expect((controller.state as ProjectCreation$CompletedState).notes, <String>[
      'scripts/get.sh',
      'Makefile',
    ]);
  });

  test('a created project has no notes, and a failed add reads none', () async {
    repository.listingScripts = <String>['scripts/get.sh'];
    controller.start(_request);
    await _until(controller, () => controller.state is ProjectCreation$CompletedState);
    expect((controller.state as ProjectCreation$CompletedState).notes, isEmpty);

    final failing = build(MemoryProjectCreationRepository()..failAt = CreationStepKind.analyze)
      ..startAdd(_member);
    addTearDown(failing.dispose);
    await _until(failing, () => failing.state is! ProjectCreation$RunningState);
    expect(failing.state, isA<ProjectCreation$FailedState>());
  });

  test('a failing notes lookup still completes the add, with no notes', () async {
    final throwing = build(_ThrowingNotesRepository());
    addTearDown(throwing.dispose);

    throwing.startAdd(_member);
    await _until(throwing, () => throwing.state is! ProjectCreation$RunningState);

    final state = throwing.state as ProjectCreation$CompletedState;
    expect(state.notes, isEmpty);
    expect(state.member, _member);
  });

  test('startAdd is dropped while another run is going, and stop applies to it', () async {
    controller
      ..startAdd(_member)
      ..start(_request)
      ..stop();
    expect(repository.requests, isEmpty);
    expect(repository.stopCalls, 1);
    await _until(controller, () => controller.state is! ProjectCreation$RunningState);
  });

  test('wraps the member checks of the repository', () async {
    repository
      ..takenPackages = <String>{'taken'}
      ..uiPackage = false
      ..uiOnSdkMaterial = true
      ..sharedPackages = false
      ..gitRepo = false;
    const path = '/Users/test/StudioProjects/shop';

    expect(
      await controller.checkMember(path, MemberKind.dartApp, 'a', 'taken'),
      MemberProblem.packageTaken,
    );
    expect(await controller.suggestedPackageName(path, 'admin'), 'shop_admin');
    expect(await controller.hasUiPackage(path), isFalse);
    expect(await controller.uiUsesSdkMaterial(path), isTrue);
    expect(await controller.hasSharedPackages(path), isFalse);
    expect(await controller.isGitRepo(path), isFalse);
  });

  test('dispose cancels the subscription', () async {
    final slow = MemoryProjectCreationRepository(step: const Duration(milliseconds: 5));
    final sliding = build(slow)..start(_request);
    await Future<void>.delayed(const Duration(milliseconds: 8));

    sliding.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(sliding.isDisposed, isTrue);
  });
}

/// A repository whose add succeeds but whose notes lookup throws.
final class _ThrowingNotesRepository with CreateOnlyProjectCreation {
  @override
  Future<String> defaultParent() async => '/Users/test/StudioProjects';

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async => null;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<CreationRun> create(NewProjectRequest request) => const Stream<CreationRun>.empty();

  @override
  Stream<CreationRun> addMember(NewMemberRequest request) async* {
    yield CreationRun(
      steps: <CreationStep>[
        for (final kind in memberStepsFor(request))
          CreationStep(kind: kind, status: CreationStepStatus.done),
      ],
    );
  }

  @override
  Future<List<String>> scriptsListingMembers(String projectPath) async =>
      throw const FileSystemException('no scripts');
}

final class _FailingRepository with CreateOnlyProjectCreation {
  @override
  Future<String> defaultParent() async => '/Users/test/StudioProjects';

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async => null;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<CreationRun> create(NewProjectRequest request) async* {
    yield CreationRun(
      steps: <CreationStep>[
        CreationStep(kind: creationStepsFor(request).first, status: CreationStepStatus.running),
      ],
    );
    throw StateError('flutter create failed');
  }
}

/// A stream whose last snapshot has the step at [failAt] failed and ends without an error.
final class _FailedStepRepository with CreateOnlyProjectCreation {
  _FailedStepRepository({this.failAt = 0});

  final int failAt;

  @override
  Future<String> defaultParent() async => '/Users/test/StudioProjects';

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async => null;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<CreationRun> create(NewProjectRequest request) async* {
    final kinds = creationStepsFor(request);
    yield CreationRun(steps: <CreationStep>[for (final kind in kinds) CreationStep(kind: kind)]);
    yield CreationRun(
      steps: <CreationStep>[
        for (var i = 0; i < kinds.length; i++)
          CreationStep(
            kind: kinds[i],
            status: i < failAt
                ? CreationStepStatus.done
                : (i == failAt ? CreationStepStatus.failed : CreationStepStatus.pending),
          ),
      ],
    );
  }
}

/// A stream that leaves the second step running and ends normally, as after a dispose of the
/// repository.
final class _InterruptedRepository with CreateOnlyProjectCreation {
  @override
  Future<String> defaultParent() async => '/Users/test/StudioProjects';

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async => null;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<CreationRun> create(NewProjectRequest request) async* {
    final kinds = creationStepsFor(request);
    yield CreationRun(
      steps: <CreationStep>[
        CreationStep(kind: kinds[0], status: CreationStepStatus.done),
        CreationStep(kind: kinds[1], status: CreationStepStatus.running),
        for (final kind in kinds.skip(2)) CreationStep(kind: kind),
      ],
    );
  }
}

/// Opens every path as project [projectId], or throws [error].
final class _Opening implements IProjectOpeningRepository {
  _Opening(this.calls);

  final List<String> calls;
  int projectId = 1;
  Exception? error;

  @override
  Future<Project> open(String path) async {
    calls.add('open $path');
    if (error case final error?) throw error;
    return Project(id: projectId, path: path, name: 'avera_booking', isFlutter: true);
  }
}

final class _Trust implements IProjectTrustRepository {
  _Trust(this.calls);

  final List<String> calls;

  @override
  Future<List<String>> agentSettingsFiles(String projectPath) async => const <String>[];

  @override
  Future<void> trust(int projectId) async => calls.add('trust $projectId');
}

final class _Rules implements IProjectRulesRepository {
  _Rules(this.calls);

  final List<String> calls;

  @override
  Future<bool> hasRules(String projectRoot) => throw UnimplementedError();

  @override
  Future<bool> canHaveRules(String projectRoot) => throw UnimplementedError();

  @override
  Future<List<ProjectRule>> builtinRules({String? projectRoot}) => throw UnimplementedError();

  @override
  Future<void> write(String projectRoot, List<ProjectRule> rules) => throw UnimplementedError();

  @override
  Future<List<String>> writeBuiltinRules(String projectPath, {Set<String> without = const {}}) =>
      throw UnimplementedError();

  @override
  Future<void> markOffered(int projectId) async => calls.add('markOffered $projectId');
}
