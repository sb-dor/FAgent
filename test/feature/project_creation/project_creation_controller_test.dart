import 'package:flutter_code_agent/src/feature/project_creation/controller/project_creation_controller.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_project_creation_repository.dart';

const _request = NewProjectRequest(
  name: 'avera_booking',
  org: 'com.example',
  parent: '/Users/test/StudioProjects',
);

Future<void> _until(ProjectCreationController controller, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  late MemoryProjectCreationRepository repository;
  late ProjectCreationController controller;

  setUp(() {
    repository = MemoryProjectCreationRepository();
    controller = ProjectCreationController(repository: repository);
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
    final failing = ProjectCreationController(repository: _FailingRepository());
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
    final failing = ProjectCreationController(repository: _FailedStepRepository());
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
    final failing = ProjectCreationController(repository: _FailedStepRepository(failAt: 1));
    addTearDown(failing.dispose);

    failing.start(_request);
    await _until(failing, () => failing.state is! ProjectCreation$RunningState);

    final state = failing.state as ProjectCreation$FailedState;
    expect((state.error as CreationStepFailed).kind, creationStepsFor(_request)[1]);
  });

  test('dispose cancels the subscription', () async {
    final slow = MemoryProjectCreationRepository(step: const Duration(milliseconds: 5));
    final sliding = ProjectCreationController(repository: slow)..start(_request);
    await Future<void>.delayed(const Duration(milliseconds: 8));

    sliding.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(sliding.isDisposed, isTrue);
  });
}

final class _FailingRepository implements IProjectCreationRepository {
  @override
  bool get isPreview => true;

  @override
  Future<String> defaultParent() async => '/Users/test/StudioProjects';

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async => null;

  @override
  Stream<List<CreationStep>> create(NewProjectRequest request) async* {
    yield <CreationStep>[
      CreationStep(kind: creationStepsFor(request).first, status: CreationStepStatus.running),
    ];
    throw StateError('flutter create failed');
  }
}

/// A stream whose last snapshot has the step at [failAt] failed and ends without an error.
final class _FailedStepRepository implements IProjectCreationRepository {
  _FailedStepRepository({this.failAt = 0});

  final int failAt;

  @override
  bool get isPreview => true;

  @override
  Future<String> defaultParent() async => '/Users/test/StudioProjects';

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async => null;

  @override
  Stream<List<CreationStep>> create(NewProjectRequest request) async* {
    final kinds = creationStepsFor(request);
    yield <CreationStep>[for (final kind in kinds) CreationStep(kind: kind)];
    yield <CreationStep>[
      for (var i = 0; i < kinds.length; i++)
        CreationStep(
          kind: kinds[i],
          status: i < failAt
              ? CreationStepStatus.done
              : (i == failAt ? CreationStepStatus.failed : CreationStepStatus.pending),
        ),
    ];
  }
}
