import 'package:flutter_code_agent/src/feature/project_rules/data/project_rules_files.dart';
import 'package:flutter_code_agent/src/feature/project_rules/models/project_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const architecture = ProjectRule(
    id: 'rule:builtin:architecture',
    name: 'architecture',
    description: 'Project layout and layers.',
    enabled: true,
  );
  const widgets = ProjectRule(
    id: 'rule:builtin:widgets',
    name: 'widgets',
    description: 'Widget conventions.',
    enabled: true,
  );
  const section =
      '<!-- flutter_code_agent:rules -->\n'
      'Before changing code, read the rules in `docs/rules/` that apply to the task. They are this '
      "project's conventions:\n"
      '\n'
      '- `docs/rules/architecture.md` — Project layout and layers.\n'
      '- `docs/rules/widgets.md` — Widget conventions.\n'
      '<!-- /flutter_code_agent:rules -->\n';

  group('agentsMdWithRules', () {
    test('a new AGENTS.md is the section alone', () {
      expect(agentsMdWithRules(null, const <ProjectRule>[architecture, widgets]), section);
    });

    test('existing text stays and the section is appended once', () {
      final once = agentsMdWithRules('# Agents\n\nOur notes.\n', const [architecture, widgets]);
      final twice = agentsMdWithRules(once, const [architecture, widgets]);

      expect(once, '# Agents\n\nOur notes.\n\n$section');
      expect(twice, once);
      expect('<!-- flutter_code_agent:rules -->'.allMatches(twice), hasLength(1));
    });

    test('the section is replaced, not duplicated', () {
      final first = agentsMdWithRules('# Agents\n', const [architecture, widgets]);

      final second = agentsMdWithRules(first, const [widgets]);

      expect(second, isNot(contains('architecture.md')));
      expect(second, contains('- `docs/rules/widgets.md` — Widget conventions.'));
      expect(second, startsWith('# Agents\n'));
      expect('<!-- flutter_code_agent:rules -->'.allMatches(second), hasLength(1));
    });

    test('a CRLF file keeps CRLF and its own bytes', () {
      const existing = '# Agents\r\n\r\nOurs, no final newline';

      final result = agentsMdWithRules(existing, const [widgets]);

      expect(result, startsWith(existing));
      expect(result.replaceAll('\r\n', ''), isNot(contains('\n')));
      expect(result, contains('- `docs/rules/widgets.md` — Widget conventions.\r\n'));
    });
  });

  group('claudeMdWithAgents', () {
    test('a missing CLAUDE.md is just the import', () {
      expect(claudeMdWithAgents(null), '@AGENTS.md\n');
    });

    test('CLAUDE.md gets @AGENTS.md once', () {
      final once = claudeMdWithAgents('# Notes');

      expect(once, '# Notes\n\n@AGENTS.md\n');
      expect(claudeMdWithAgents(once), once);
    });

    test('an existing @AGENTS.md, spaced or as @./AGENTS.md, adds nothing', () {
      for (final text in <String>['@AGENTS.md\n', '# A\n  @AGENTS.md  \n', '# A\n@./AGENTS.md\n']) {
        expect(claudeMdWithAgents(text), text, reason: text);
      }
    });
  });

  test('ruleBody drops the frontmatter', () {
    expect(ruleBody('---\nname: a\ndescription: "A"\n---\n\n# A\n\nText.\n'), '# A\n\nText.\n');
    expect(ruleBody('# No frontmatter\n'), '# No frontmatter\n');
  });
}
