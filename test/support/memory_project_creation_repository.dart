import 'dart:async';

import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';

/// [IProjectCreationRepository] for tests: no file system, no timers beyond [step].
///
/// [existing] are the full paths [checkTarget] reports as taken. [create] runs the steps of
/// [creationStepsFor] one by one and records the request in [requests].
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
        // Each step goes running, then done.
        final snapshots = <List<CreationStep>>[];
        for (var i = 0; i < kinds.length; i++) {
          for (final status in [CreationStepStatus.running, CreationStepStatus.done]) {
            snapshots.add([
              for (var j = 0; j < kinds.length; j++)
                CreationStep(
                  kind: kinds[j],
                  status: j < i
                      ? CreationStepStatus.done
                      : (j == i ? status : CreationStepStatus.pending),
                ),
            ]);
          }
        }
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
