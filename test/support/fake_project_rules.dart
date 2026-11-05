import 'dart:async';

import 'package:flutter_code_agent/src/feature/project_rules/data/project_rules_repository.dart';
import 'package:flutter_code_agent/src/feature/project_rules/models/project_rule.dart';

/// [IProjectRulesRepository] in memory. [withRules] holds the project folders that have
/// `docs/rules`; with [allHaveRules] every folder has them, so nothing is ever offered (the default
/// of `testDependencies`).
final class FakeProjectRules implements IProjectRulesRepository {
  /// Creates the fake.
  FakeProjectRules({this.allHaveRules = false});

  /// Every project counts as having `docs/rules`.
  final bool allHaveRules;

  /// Project folders with `docs/rules`.
  final Set<String> withRules = <String>{};

  /// Every [write]: the project folder and the rule names.
  final List<(String, List<String>)> written = <(String, List<String>)>[];

  /// Every [markOffered].
  final List<int> offered = <int>[];

  /// Thrown by [write] when set.
  Exception? writeError;

  /// Completes [hasRules] when set, so a test can hold the check.
  Completer<void>? hold;

  /// The built-in rules it lists.
  static const List<ProjectRule> rules = <ProjectRule>[
    ProjectRule(id: 'rule:builtin:a', name: 'a', description: 'Rule A', enabled: true),
    ProjectRule(id: 'rule:builtin:b', name: 'b', description: 'Rule B', enabled: false),
  ];

  @override
  Future<bool> hasRules(String projectRoot) async {
    await hold?.future;
    return allHaveRules || withRules.contains(projectRoot);
  }

  @override
  Future<List<ProjectRule>> builtinRules() async => rules;

  @override
  Future<void> write(String projectRoot, List<ProjectRule> rules) async {
    if (writeError case final error?) throw error;
    written.add((projectRoot, <String>[for (final rule in rules) rule.name]));
    withRules.add(projectRoot);
  }

  @override
  Future<void> markOffered(int projectId) async => offered.add(projectId);
}
