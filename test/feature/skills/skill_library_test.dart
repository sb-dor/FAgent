import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';
import 'package:flutter_test/flutter_test.dart';

KnowledgeItem _item(KnowledgeKind kind, SkillSource source, String name) => KnowledgeItem(
  id: '${kind.name}:${source.name}:$name',
  kind: kind,
  source: source,
  name: name,
  title: name,
  description: 'd',
  path: '/$name',
);

void main() {
  test('only project skills are invocable', () {
    expect(_item(KnowledgeKind.skill, SkillSource.project, 'a').invocable, isTrue);
    expect(_item(KnowledgeKind.skill, SkillSource.user, 'a').invocable, isFalse);
    expect(_item(KnowledgeKind.skill, SkillSource.builtin, 'a').invocable, isFalse);
    expect(_item(KnowledgeKind.rule, SkillSource.project, 'a').invocable, isFalse);
  });

  test('byId finds skills and rules', () {
    final skill = _item(KnowledgeKind.skill, SkillSource.builtin, 'a');
    final rule = _item(KnowledgeKind.rule, SkillSource.user, 'b');
    final library = SkillLibrary(skills: [skill], rules: [rule]);

    expect(library.byId('skill:builtin:a'), skill);
    expect(library.byId('rule:user:b'), rule);
    expect(library.byId('rule:user:missing'), isNull);
    expect(SkillLibrary.empty.byId('skill:builtin:a'), isNull);
  });
}
