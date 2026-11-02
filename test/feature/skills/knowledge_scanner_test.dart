import 'dart:io';

import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/skills/data/knowledge_scanner.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skill_states.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('knowledge_scanner_test'));

  tearDown(() => root.deleteSync(recursive: true));

  KnowledgeItem? scan() => agentsItem(projectRoot: root.path, snapshot: snapshotAgents(root.path));

  test('a project with AGENTS.md has a read-only project rule for it', () {
    File('${root.path}/AGENTS.md').writeAsStringSync('# Rules\nNo frontmatter here.\n');

    final item = scan()!;

    expect(item.id, 'rule:project:AGENTS');
    expect(item.kind, KnowledgeKind.rule);
    expect(item.source, SkillSource.project);
    expect(item.name, 'AGENTS');
    expect(item.path, '${root.path}/AGENTS.md');
    expect(item.readOnly, isTrue);
    expect(item.alwaysOn, isTrue);
    expect(item.problem, isNull);
    expect(item.revision, isNotEmpty);
  });

  test('a project without AGENTS.md has no such rule', () {
    expect(snapshotAgents(root.path), isEmpty);
    expect(scan(), isNull);
  });

  test('a folder called AGENTS.md is not the rule', () {
    Directory('${root.path}/AGENTS.md').createSync();

    expect(scan(), isNull);
  });

  test('the revision changes with the file', () {
    final file = File('${root.path}/AGENTS.md')..writeAsStringSync('a');
    final before = scan()!.revision;

    file.writeAsStringSync('abc');

    expect(scan()!.revision, isNot(before));
  });

  test('the skill_states rows do not switch the rule off', () {
    File('${root.path}/AGENTS.md').writeAsStringSync('rules');
    final item = scan()!;

    final library = applySkillStates(
      [item],
      [
        const SkillStateRow(id: 1, skillId: agentsRuleId, enabled: false),
        const SkillStateRow(id: 2, skillId: agentsRuleId, projectId: 7, enabled: false),
      ],
      7,
    );

    final applied = library.byId(agentsRuleId)!;
    expect(applied.enabled, isTrue);
    expect(applied.enabledGlobally, isTrue);
    expect(applied.exceptions, isEmpty);
  });
}
