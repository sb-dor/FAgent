import 'dart:async';

import 'package:flutter_code_agent/src/feature/project_creation/data/fake_project_creation_repository.dart'
    show fakeStepOutput, kFakeStepDurations;
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';

/// [IProjectCreationRepository] for tests: no file system, no timers beyond [step].
///
/// [existing] are the full paths [checkTarget] reports as taken. [create] plays the same run as the
/// fake repository (first all pending, then each step of [creationStepsFor] with its output and
/// duration) and records the request in [requests].
final class MemoryProjectCreationRepository implements IProjectCreationRepository {
  /// Creates the repository.
  MemoryProjectCreationRepository({
    this.parent = '/Users/test/StudioProjects',
    Set<String> existing = const <String>{},
    this.step = Duration.zero,
  }) : _existing = <String>{...existing};

  /// What [defaultParent] returns.
  final String parent;

  /// The time between two snapshots of [create].
  final Duration step;

  final Set<String> _existing;

  /// The requests [create] was called with.
  final List<NewProjectRequest> requests = <NewProjectRequest>[];

  @override
  bool get isPreview => true;

  @override
  Future<String> defaultParent() async => parent;

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async =>
      _existing.contains('$parent/$name') ? TargetProblem.exists : null;

  @override
  Stream<List<CreationStep>> create(NewProjectRequest request) {
    requests.add(request);
    final controller = StreamController<List<CreationStep>>();
    Timer? timer;
    controller
      ..onListen = () {
        final kinds = creationStepsFor(request);
        // Like the fake repository: all pending first, then each step starts, prints its lines
        // one by one and finishes.
        var steps = <CreationStep>[for (final kind in kinds) CreationStep(kind: kind)];
        final snapshots = <List<CreationStep>>[];
        void change(int index, CreationStep Function(CreationStep) apply) {
          steps = List<CreationStep>.of(steps)..[index] = apply(steps[index]);
          snapshots.add(steps);
        }

        for (var i = 0; i < kinds.length; i++) {
          final output = fakeStepOutput(kinds[i], request.name);
          change(i, (step) => step.copyWith(status: CreationStepStatus.running));
          for (var line = 1; line <= output.length; line++) {
            change(i, (step) => step.copyWith(output: output.sublist(0, line)));
          }
          change(
            i,
            (step) =>
                step.copyWith(status: CreationStepStatus.done, took: kFakeStepDurations[step.kind]),
          );
        }
        controller.add(<CreationStep>[for (final kind in kinds) CreationStep(kind: kind)]);
        var next = 0;
        void emit() {
          timer = Timer(step, () {
            if (controller.isClosed) return;
            controller.add(snapshots[next++]);
            if (next == snapshots.length) {
              controller.close();
            } else {
              emit();
            }
          });
        }

        emit();
      }
      ..onCancel = () {
        timer?.cancel();
        if (!controller.isClosed) controller.close();
      };
    return controller.stream;
  }
}
