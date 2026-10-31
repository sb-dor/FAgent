import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:path/path.dart' as p;

/// How long each made-up step "took".
const Map<CreationStepKind, Duration> kFakeStepDurations = <CreationStepKind, Duration>{
  CreationStepKind.flutterCreate: Duration(seconds: 6),
  CreationStepKind.gitInit: Duration(seconds: 1),
  CreationStepKind.agentSetup: Duration(seconds: 3),
  CreationStepKind.analyze: Duration(seconds: 2),
  CreationStepKind.firstCommit: Duration(seconds: 1),
};

/// The lines a made-up step prints.
List<String> _outputOf(CreationStepKind kind, String name) => switch (kind) {
  CreationStepKind.flutterCreate => <String>['Creating project $name...', 'Wrote 130 files.'],
  CreationStepKind.agentSetup => const <String>[
    '✎ lib/src/common/localization/intl_en.arb',
    '✎ lib/src/feature/initialization/…',
    '⌁ flutter pub add control drift freezed_annotation…',
    '⌁ dart run build_runner build',
  ],
  CreationStepKind.analyze => const <String>['No issues found!'],
  CreationStepKind.gitInit || CreationStepKind.firstCommit => const <String>[],
};

/// Looks at the real disk to check a target, but creates nothing: [create] plays a made-up run
/// until the Flutter tooling is wired in (milestone M4).
final class FakeProjectCreationRepositoryImpl implements IProjectCreationRepository {
  /// Creates the repository. [step] is the time between two changes of a made-up run; [home]
  /// defaults to `$HOME`.
  FakeProjectCreationRepositoryImpl({
    required this._database,
    this.step = const Duration(milliseconds: 700),
    String? home,
  }) : _home = home ?? Platform.environment['HOME'] ?? p.separator;

  final AppDatabase _database;
  final String _home;

  /// The time between two changes of a made-up run.
  final Duration step;

  @override
  bool get isPreview => true;

  @override
  Future<String> defaultParent() async {
    final last =
        await (_database.select(_database.projectsTable)
              ..where((t) => t.lastOpenedAt.isNotNull())
              ..orderBy([(t) => OrderingTerm.desc(t.lastOpenedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (last != null) {
      final parent = p.dirname(last.path);
      if (Directory(parent).existsSync()) return parent;
    }
    final studio = p.join(_home, 'StudioProjects');
    return Directory(studio).existsSync() ? studio : _home;
  }

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async {
    if (!Directory(parent).existsSync()) return TargetProblem.parentMissing;
    final type = FileSystemEntity.typeSync(p.join(parent, name), followLinks: false);
    return type == FileSystemEntityType.notFound ? null : TargetProblem.exists;
  }

  @override
  Stream<List<CreationStep>> create(NewProjectRequest request) {
    final controller = StreamController<List<CreationStep>>();
    Timer? timer;
    controller
      ..onListen = () {
        var steps = <CreationStep>[
          for (final kind in creationStepsFor(request)) CreationStep(kind: kind),
        ];
        final changes = _changes(steps, request.name).toList();
        var next = 0;
        controller.add(steps);
        void schedule() {
          timer = Timer(step, () {
            if (controller.isClosed) return;
            final (index, change) = changes[next++];
            steps = List<CreationStep>.of(steps)..[index] = change(steps[index]);
            controller.add(steps);
            if (next == changes.length) {
              controller.close();
            } else {
              schedule();
            }
          });
        }

        schedule();
      }
      ..onCancel = () {
        timer?.cancel();
        if (!controller.isClosed) controller.close();
      };
    return controller.stream;
  }

  /// The changes of a run, one per snapshot: a step starts, prints its lines one by one, finishes.
  static Iterable<(int, CreationStep Function(CreationStep))> _changes(
    List<CreationStep> steps,
    String name,
  ) sync* {
    for (var i = 0; i < steps.length; i++) {
      final output = _outputOf(steps[i].kind, name);
      yield (i, (step) => step.copyWith(status: CreationStepStatus.running));
      for (var line = 1; line <= output.length; line++) {
        yield (i, (step) => step.copyWith(output: output.sublist(0, line)));
      }
      yield (
        i,
        (step) =>
            step.copyWith(status: CreationStepStatus.done, took: kFakeStepDurations[step.kind]),
      );
    }
  }
}
