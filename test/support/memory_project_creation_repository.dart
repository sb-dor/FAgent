import 'dart:async';

import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_member_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:path/path.dart' as p;

/// How long each made-up step "took".
const Map<CreationStepKind, Duration> _stepDurations = <CreationStepKind, Duration>{
  CreationStepKind.flutterCreate: Duration(seconds: 6),
  CreationStepKind.gitInit: Duration(seconds: 1),
  CreationStepKind.skeleton: Duration(seconds: 3),
  CreationStepKind.analyze: Duration(seconds: 2),
  CreationStepKind.rules: Duration(milliseconds: 200),
  CreationStepKind.firstCommit: Duration(seconds: 1),
  CreationStepKind.memberCreate: Duration(seconds: 4),
  CreationStepKind.pubGet: Duration(seconds: 2),
  CreationStepKind.commit: Duration(milliseconds: 300),
};

/// The lines a made-up step of the project [name] prints.
List<String> _stepOutput(CreationStepKind kind, String name) => switch (kind) {
  CreationStepKind.flutterCreate => <String>['Creating project $name...', 'Wrote 130 files.'],
  CreationStepKind.skeleton => const <String>[
    '✎ lib/src/common/localization/intl_en.arb',
    '✎ lib/src/feature/initialization/…',
    '⌁ flutter pub add control drift freezed_annotation…',
    '⌁ dart run build_runner build',
  ],
  CreationStepKind.analyze => const <String>['No issues found!'],
  CreationStepKind.rules => const <String>['✎ docs/rules/architecture.md'],
  CreationStepKind.gitInit || CreationStepKind.firstCommit => const <String>[],
  CreationStepKind.memberCreate => <String>['Creating project $name...', 'Wrote 40 files.'],
  CreationStepKind.pubGet => const <String>['Got dependencies!'],
  CreationStepKind.workspace || CreationStepKind.commit => const <String>[],
};

/// The add-to-project half of [IProjectCreationRepository] for fakes that only create projects:
/// no member can be added, every check passes.
mixin CreateOnlyProjectCreation implements IProjectCreationRepository {
  @override
  Stream<CreationRun> addMember(NewMemberRequest request) => const Stream<CreationRun>.empty();

  @override
  Future<MemberProblem?> checkMember(
    String projectPath,
    MemberKind kind,
    String folder,
    String packageName,
  ) async => null;

  @override
  Future<String> suggestedPackageName(String projectPath, String folder) async =>
      '${p.basename(projectPath)}_$folder';

  @override
  Future<bool> hasUiPackage(String projectPath) async => true;

  @override
  Future<bool> isGitRepo(String projectPath) async => true;

  @override
  Future<List<String>> scriptsListingMembers(String projectPath) async => const <String>[];
}

/// [IProjectCreationRepository] for tests: no file system, no timers beyond [step].
///
/// [existing] are the full paths [checkTarget] and [checkMember] report as taken. [create] plays a
/// made-up run (first all pending, then each step of [creationStepsFor] with its output and
/// duration) and records the request in [requests]; [addMember] does the same with
/// [memberStepsFor] and [memberRequests]. With [failAt] set, that step fails and the run ends there.
/// [stop] only counts in [stopCalls].
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

  /// The step that fails; the run ends with it. `null` for a run that succeeds.
  CreationStepKind? failAt;

  /// How many times [stop] was called.
  int stopCalls = 0;

  /// The requests [create] was called with.
  final List<NewProjectRequest> requests = <NewProjectRequest>[];

  /// The requests [addMember] was called with.
  final List<NewMemberRequest> memberRequests = <NewMemberRequest>[];

  /// The package names [checkMember] reports as taken.
  Set<String> takenPackages = <String>{};

  /// What [hasUiPackage] returns.
  bool uiPackage = true;

  /// What [isGitRepo] returns.
  bool gitRepo = true;

  /// What [scriptsListingMembers] returns.
  List<String> listingScripts = const <String>[];

  @override
  Future<String> defaultParent() async => parent;

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async =>
      _existing.contains('$parent/$name') ? TargetProblem.exists : null;

  @override
  Future<MemberProblem?> checkMember(
    String projectPath,
    MemberKind kind,
    String folder,
    String packageName,
  ) async {
    if (_existing.contains('$projectPath/${kind.parent}/$folder')) {
      return MemberProblem.folderExists;
    }
    return takenPackages.contains(packageName) ? MemberProblem.packageTaken : null;
  }

  @override
  Future<String> suggestedPackageName(String projectPath, String folder) async =>
      '${p.basename(projectPath)}_$folder';

  @override
  Future<bool> hasUiPackage(String projectPath) async => uiPackage;

  @override
  Future<bool> isGitRepo(String projectPath) async => gitRepo;

  @override
  Future<List<String>> scriptsListingMembers(String projectPath) async => listingScripts;

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> dispose() async {}

  @override
  Stream<CreationRun> create(NewProjectRequest request) {
    requests.add(request);
    return _play(creationStepsFor(request), request.name);
  }

  @override
  Stream<CreationRun> addMember(NewMemberRequest request) {
    memberRequests.add(request);
    return _play(memberStepsFor(request), request.packageName);
  }

  /// The made-up run of [kinds], printing [name] where a step names the project.
  Stream<CreationRun> _play(List<CreationStepKind> kinds, String name) {
    final controller = StreamController<CreationRun>();
    Timer? timer;
    controller
      ..onListen = () {
        // All pending first, then each step starts, prints its lines
        // one by one and finishes.
        var steps = <CreationStep>[for (final kind in kinds) CreationStep(kind: kind)];
        final snapshots = <CreationRun>[];
        void change(int index, CreationStep Function(CreationStep) apply) {
          steps = List<CreationStep>.of(steps)..[index] = apply(steps[index]);
          snapshots.add(CreationRun(steps: steps));
        }

        for (var i = 0; i < kinds.length; i++) {
          final output = _stepOutput(kinds[i], name);
          change(i, (step) => step.copyWith(status: CreationStepStatus.running));
          if (kinds[i] == failAt) {
            change(i, (step) => step.copyWith(status: CreationStepStatus.failed));
            break;
          }
          for (var line = 1; line <= output.length; line++) {
            change(i, (step) => step.copyWith(output: output.sublist(0, line)));
          }
          change(
            i,
            (step) =>
                step.copyWith(status: CreationStepStatus.done, took: _stepDurations[step.kind]),
          );
        }
        controller.add(
          CreationRun(steps: <CreationStep>[for (final kind in kinds) CreationStep(kind: kind)]),
        );
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
