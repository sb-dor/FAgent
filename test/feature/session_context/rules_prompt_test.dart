import 'dart:convert';

import 'package:flutter_code_agent/src/feature/session_context/data/rules_prompt.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_test/flutter_test.dart';

RuleText _rule(SkillSource source, String name, String text) =>
    (source: source, name: name, text: text);

void main() {
  test('starts with the priority line', () {
    final prompt = buildRulesPrompt(rules: [], skills: []);

    expect(prompt, startsWith('Later rules override earlier ones.'));
  });

  test('puts built-in, user and project rules in that order, then AGENTS.md', () {
    final prompt = buildRulesPrompt(
      rules: [
        _rule(SkillSource.project, 'p', 'project text'),
        _rule(SkillSource.user, 'u', 'user text'),
        _rule(SkillSource.builtin, 'b1', 'builtin one'),
        _rule(SkillSource.builtin, 'b2', 'builtin two'),
      ],
      skills: [],
      agentsMd: 'agents text',
    );

    final at = [
      for (final marker in ['## b1', '## b2', '## u', '## p', '## AGENTS.md'])
        prompt.indexOf(marker),
    ];
    expect(at, everyElement(isNonNegative));
    expect(at, orderedEquals([...at]..sort()));
    expect(prompt, contains('## p\nproject text'));
    expect(prompt, contains('## AGENTS.md\nagents text'));
  });

  test('strips the frontmatter of a rule', () {
    final prompt = buildRulesPrompt(
      rules: [_rule(SkillSource.builtin, 'r', '---\nname: r\ndescription: d\n---\n# Body\n')],
      skills: [],
    );

    expect(prompt, contains('## r\n# Body'));
    expect(prompt, isNot(contains('description: d')));
  });

  test('leaves AGENTS.md out when CLAUDE.md imports it', () {
    final prompt = buildRulesPrompt(
      rules: [],
      skills: [],
      agentsMd: 'agents text',
      claudeMd: 'x\n@AGENTS.md\n',
    );

    expect(prompt, isNot(contains('AGENTS.md')));
    expect(prompt, isNot(contains('agents text')));
  });

  test('keeps AGENTS.md when CLAUDE.md only mentions it', () {
    final prompt = buildRulesPrompt(
      rules: [],
      skills: [],
      agentsMd: 'agents text',
      claudeMd: 'See @AGENTS.md.\n',
    );

    expect(prompt, contains('## AGENTS.md\nagents text'));
  });

  test('leaves a blank AGENTS.md out', () {
    final prompt = buildRulesPrompt(rules: [], skills: [], agentsMd: ' \n');

    expect(prompt, isNot(contains('AGENTS.md')));
  });

  test('cuts a long user rule at the limit and marks it', () {
    final prompt = buildRulesPrompt(
      rules: [_rule(SkillSource.user, 'big', 'a' * 200 * 1024)],
      skills: [],
    );

    expect(prompt, contains('${'a' * ruleFileLimit}\n[truncated]'));
    expect(prompt, isNot(contains('a' * (ruleFileLimit + 1))));
  });

  test('cuts on a character boundary', () {
    // Each "я" takes two bytes; an odd limit would fall in the middle of one.
    final prompt = buildRulesPrompt(
      rules: [_rule(SkillSource.project, 'big', 'я' * ruleFileLimit)],
      skills: [],
    );

    final body = prompt.split('## big\n').last.replaceFirst('\n[truncated]\n', '');
    expect(utf8.encode(body), hasLength(lessThanOrEqualTo(ruleFileLimit)));
    expect(body, 'я' * (ruleFileLimit ~/ 2));
    expect(prompt, endsWith('[truncated]\n'));
  });

  test('cuts a long AGENTS.md but never a built-in rule', () {
    final long = 'b' * 200 * 1024;
    final prompt = buildRulesPrompt(
      rules: [_rule(SkillSource.builtin, 'big', long)],
      skills: [],
      agentsMd: long,
    );

    expect(prompt, contains('## big\n$long\n\n## AGENTS.md\n${'b' * ruleFileLimit}\n[truncated]'));
    expect('[truncated]'.allMatches(prompt), hasLength(1));
  });

  test('lists the skills, and nothing when there are none', () {
    final prompt = buildRulesPrompt(
      rules: [],
      skills: [
        (name: 'widget-test', description: 'Write widget tests'),
        (name: 'drift', description: 'Migrate\nthe database'),
      ],
    );

    expect(
      prompt,
      contains(
        '## Skills from flutter_code_agent\n'
        '- widget-test — Write widget tests\n'
        '- drift — Migrate the database',
      ),
    );
    expect(buildRulesPrompt(rules: [], skills: []), isNot(contains('Skills from')));
  });
}
