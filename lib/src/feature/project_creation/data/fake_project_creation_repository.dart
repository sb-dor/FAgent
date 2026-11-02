import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:l/l.dart';
import 'package:path/path.dart' as p;

/// How long each made-up step "took".
const Map<CreationStepKind, Duration> kFakeStepDurations = <CreationStepKind, Duration>{
  CreationStepKind.flutterCreate: Duration(seconds: 6),
  CreationStepKind.gitInit: Duration(seconds: 1),
  CreationStepKind.skeleton: Duration(seconds: 3),
  CreationStepKind.analyze: Duration(seconds: 2),
  CreationStepKind.firstCommit: Duration(seconds: 1),
};

/// The lines a made-up step of the project [name] prints.
List<String> fakeStepOutput(CreationStepKind kind, String name) => switch (kind) {
  CreationStepKind.flutterCreate => <String>['Creating project $name...', 'Wrote 130 files.'],
  CreationStepKind.skeleton => const <String>[
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

  Timer? _timer;
  StreamController<CreationRun>? _controller;

  @override
  bool get isPreview => true;

  @override
  Future<String> defaultParent() async {
    try {
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
    } on Object catch (error, stackTrace) {
      l.w('Project creation | default folder | falling back to home: $error', stackTrace);
      return _home;
    }
  }

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async {
    if (!Directory(parent).existsSync()) return TargetProblem.parentMissing;
    final type = FileSystemEntity.typeSync(p.join(parent, name), followLinks: false);
    return type == FileSystemEntityType.notFound ? null : TargetProblem.exists;
  }

  @override
  Stream<CreationRun> create(NewProjectRequest request) {
    final controller = _controller = StreamController<CreationRun>();
    controller
      ..onListen = () {
        var steps = <CreationStep>[
          for (final kind in creationStepsFor(request)) CreationStep(kind: kind),
        ];
        final changes = _changes(steps, request.name).toList();
        var next = 0;
        controller.add(CreationRun(steps: steps));
        void schedule() {
          _timer = Timer(step, () {
            if (controller.isClosed) return;
            final (index, change) = changes[next++];
            steps = List<CreationStep>.of(steps)..[index] = change(steps[index]);
            controller.add(CreationRun(steps: steps));
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
        _timer?.cancel();
        if (!controller.isClosed) controller.close();
      };
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    final controller = _controller;
    if (controller != null && !controller.isClosed) await controller.close();
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _controller?.close();
  }

  /// The changes of a run, one per snapshot: a step starts, prints its lines one by one, finishes.
  static Iterable<(int, CreationStep Function(CreationStep))> _changes(
    List<CreationStep> steps,
    String name,
  ) sync* {
    for (var i = 0; i < steps.length; i++) {
      final output = fakeStepOutput(steps[i].kind, name);
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
