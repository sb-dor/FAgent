import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/data/permission_rules_repository.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/models/permission_rules_exceptions.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:path/path.dart' as p;

part 'permission_rules_controller.freezed.dart';

/// What a project's `.claude/settings.local.json` holds.
@freezed
sealed class ProjectRules with _$ProjectRules {
  /// The saved [rules] of the project; empty when it has none.
  const factory ProjectRules.rules(List<String> rules) = ProjectRules$Rules;

  /// The file at [path] could not be read.
  const factory ProjectRules.unreadable(String path) = ProjectRules$Unreadable;
}

@freezed
sealed class PermissionRulesState with _$PermissionRulesState {
  /// Nothing was loaded yet.
  const factory PermissionRulesState.initial() = PermissionRules$InitialState;

  /// The first load is running.
  const factory PermissionRulesState.inProgress() = PermissionRules$InProgressState;

  /// The rules of every project that was loaded, by `Project.id`.
  const factory PermissionRulesState.completed(Map<int, ProjectRules> rules) =
      PermissionRules$CompletedState;
}

/// Reads the saved permission rules of the projects and removes them.
///
/// One thing at a time: a load or a removal waits for the one before it. A reload after the first
/// load replaces the values without going back to `inProgress`, so the cards do not blink.
final class PermissionRulesController extends StateController<PermissionRulesState>
    with SequentialControllerHandler {
  PermissionRulesController({
    required this._repository,
    this.onRemoveFailed,
    super.initialState = const PermissionRulesState.initial(),
  });

  final IPermissionRulesRepository _repository;

  /// Called with the error when a rule could not be removed. The project is read again either
  /// way, so the section shows what the file holds.
  final void Function(Object error)? onRemoveFailed;

  Map<int, ProjectRules> _rules = const <int, ProjectRules>{};

  /// Reads the rules of every one of [projects]. Projects that are no longer listed are dropped.
  void load(List<Project> projects) => handle(() async {
    if (isDisposed) return;
    if (state is PermissionRules$InitialState) {
      setState(const PermissionRulesState.inProgress());
    }
    final loaded = <int, ProjectRules>{
      for (final project in projects) project.id: await _read(project),
    };
    if (isDisposed) return;
    setState(PermissionRulesState.completed(_rules = loaded));
  }, error: (error, stackTrace) async => setState(PermissionRulesState.completed(_rules)));

  /// Removes [rule] from [project], then reads that project again.
  void remove(Project project, String rule) => handle(() async {
    if (isDisposed) return;
    try {
      await _repository.remove(project.path, rule);
    } on Object catch (error) {
      onRemoveFailed?.call(error);
    }
    final updated = await _read(project);
    if (isDisposed) return;
    setState(
      PermissionRulesState.completed(_rules = <int, ProjectRules>{..._rules, project.id: updated}),
    );
  }, error: (error, stackTrace) async => setState(PermissionRulesState.completed(_rules)));

  Future<ProjectRules> _read(Project project) async {
    try {
      return ProjectRules.rules(await _repository.rules(project.path));
    } on PermissionRulesUnreadableException catch (error) {
      return ProjectRules.unreadable(error.path);
    } on Object {
      // Any other failure (no access, a vanished folder) leaves the file unusable too.
      return ProjectRules.unreadable(p.join(project.path, '.claude', 'settings.local.json'));
    }
  }
}
