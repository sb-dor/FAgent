import 'dart:io';

import 'package:flutter_code_agent/src/feature/project_rules/data/project_rules_files.dart';
import 'package:flutter_code_agent/src/feature/project_rules/models/project_rule.dart';
import 'package:flutter_code_agent/src/feature/projects/data/projects_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:path/path.dart' as p;

/// The app's built-in rules as files of a project: `docs/rules/<name>.md`, the section of
/// `AGENTS.md` that points agents to them, and the `@AGENTS.md` line of `CLAUDE.md`.
abstract interface class IProjectRulesRepository {
  /// Whether the project in [projectRoot] has a `docs/rules` folder.
  Future<bool> hasRules(String projectRoot);

  /// The built-in rules, in library order, with their switches.
  Future<List<ProjectRule>> builtinRules();

  /// Writes [rules] into the project in [projectRoot] and updates its `AGENTS.md` and `CLAUDE.md`.
  ///
  /// Throws [FileSystemException] when a file cannot be written.
  Future<void> write(String projectRoot, List<ProjectRule> rules);

  /// Remembers that the rules were offered to project [projectId].
  Future<void> markOffered(int projectId);
}

/// [IProjectRulesRepository] on the skills library (the rules' texts) and the projects table.
final class ProjectRulesRepositoryImpl implements IProjectRulesRepository {
  /// Creates the repository.
  ProjectRulesRepositoryImpl({required this._skills, required this._projects});

  final ISkillsRepository _skills;
  final IProjectsRepository _projects;

  @override
  Future<bool> hasRules(String projectRoot) async =>
      FileSystemEntity.isDirectorySync(p.join(projectRoot, projectRulesFolder));

  @override
  Future<List<ProjectRule>> builtinRules() async {
    final library = await _skills.watch().first;
    return <ProjectRule>[
      for (final rule in library.rules)
        if (rule.source == SkillSource.builtin)
          ProjectRule(
            id: rule.id,
            name: rule.name,
            description: rule.description,
            // The global switch: new projects and the offer have no project exception yet.
            enabled: rule.enabledGlobally,
          ),
    ];
  }

  @override
  Future<void> write(String projectRoot, List<ProjectRule> rules) async {
    final folder = Directory(p.join(projectRoot, projectRulesFolder));
    await folder.create(recursive: true);
    for (final rule in rules) {
      final text = await _skills.read(rule.id);
      await File(p.join(folder.path, '${rule.name}.md')).writeAsString(ruleBody(text));
    }
    await _update(p.join(projectRoot, 'AGENTS.md'), (text) => agentsMdWithRules(text, rules));
    await _update(p.join(projectRoot, 'CLAUDE.md'), claudeMdWithAgents);
  }

  /// Rewrites the file at [path] (`null` text when it does not exist) with [change].
  static Future<void> _update(String path, String Function(String? text) change) async {
    final file = File(path);
    final text = file.existsSync() ? await file.readAsString() : null;
    final changed = change(text);
    if (changed != text) await file.writeAsString(changed);
  }

  @override
  Future<void> markOffered(int projectId) => _projects.markRulesOffered(projectId);
}
