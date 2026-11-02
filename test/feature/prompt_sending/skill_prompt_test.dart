import 'package:flutter_code_agent/src/feature/prompt_sending/models/skill_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('leadingCommand', () {
    test('splits the leading /name from the rest', () {
      expect(leadingCommand('/feature-architecture add a todo feature'), (
        name: 'feature-architecture',
        rest: 'add a todo feature',
      ));
      expect(leadingCommand('  /name   two\nlines  '), (name: 'name', rest: 'two\nlines'));
    });

    test('a command alone has an empty rest', () {
      expect(leadingCommand('/name'), (name: 'name', rest: ''));
      expect(leadingCommand('/name  '), (name: 'name', rest: ''));
    });

    test('text that does not start with a command has none', () {
      expect(leadingCommand('use /name'), isNull);
      expect(leadingCommand('/'), isNull);
      expect(leadingCommand(''), isNull);
      expect(leadingCommand('/ name'), isNull);
    });
  });

  test('an empty rest asks the agent to use the skill', () {
    expect(skillPromptText('feature-architecture', ''), 'Use the feature-architecture skill.');
    expect(skillPromptText('feature-architecture', 'add a todo'), 'add a todo');
  });

  test('the skill resource embeds SKILL.md as markdown', () {
    expect(skillResource('feature-architecture', '# Feature\n'), <String, Object?>{
      'type': 'resource',
      'resource': <String, Object?>{
        'uri': 'skill://feature-architecture/SKILL.md',
        'mimeType': 'text/markdown',
        'text': '# Feature\n',
      },
    });
  });
}
