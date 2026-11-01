import 'package:flutter_code_agent/src/common/localization/generated/generated_localization_en.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/slash_command.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/slash_commands.dart';
import 'package:flutter_code_agent/src/feature/skills/models/chat_skills.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_test/flutter_test.dart';

ChatSkill _skill(String name, SkillSource source, {bool enabled = true, String description = ''}) =>
    ChatSkill(
      id: 'skill:${source.name}:$name',
      name: name,
      description: description,
      source: source,
      enabled: enabled,
      invocable: source != SkillSource.git,
    );

void main() {
  final localization = GeneratedLocalizationEn();
  group('skillCommands', () {
    test('lists the skills that are on, of every source; a git skill cannot be run yet', () {
      final commands = skillCommands(
        ChatSkills(
          projectName: 'p',
          skills: <ChatSkill>[
            _skill('release', SkillSource.project, description: 'Before a release'),
            _skill('feature-architecture', SkillSource.builtin),
            _skill('off', SkillSource.project, enabled: false),
            _skill('from-git', SkillSource.git),
          ],
        ),
        localization,
      );

      expect(commands, const <SlashCommand>[
        SlashCommand(name: 'release', source: SlashSource.skill, description: 'Before a release'),
        SlashCommand(name: 'feature-architecture', source: SlashSource.skill),
        SlashCommand(
          name: 'from-git',
          source: SlashSource.skill,
          enabled: false,
          hint: 'Coming in M3',
        ),
      ]);
    });

    test('of equal names the first one wins, and a name with whitespace is skipped', () {
      final commands = skillCommands(
        ChatSkills(
          projectName: 'p',
          skills: <ChatSkill>[
            _skill('same', SkillSource.project),
            _skill('same', SkillSource.user),
            _skill('two words', SkillSource.project),
          ],
        ),
        localization,
      );

      expect([for (final c in commands) c.name], <String>['same']);
      expect(commands.single.enabled, isTrue);
    });
  });

  group('slashMenuRows', () {
    final skills = ChatSkills(
      projectName: 'p',
      skills: <ChatSkill>[_skill('run-tests', SkillSource.project)],
    );
    const agent = <SlashCommand>[SlashCommand(name: 'compact', source: SlashSource.agent)];

    test('skills come before the app and the agent', () {
      final rows = slashMenuRows(
        localization: localization,
        skills: skills,
        agent: agent,
        query: '',
      );

      expect({for (final r in rows) r.source}, SlashSource.values.toSet());
      expect(rows.first.name, 'run-tests');
      expect(rows.first.source, SlashSource.skill);
      expect(rows.last.name, 'compact');
    });

    test('the query narrows the skills too', () {
      final rows = slashMenuRows(
        localization: localization,
        skills: skills,
        agent: agent,
        query: 'tests',
      );

      expect([for (final r in rows) r.name], <String>['run-tests']);
    });

    test('an agent command named like a skill is dropped (the agent lists skills too)', () {
      const duplicated = <SlashCommand>[
        SlashCommand(name: 'run-tests', source: SlashSource.agent, description: 'Same skill'),
        SlashCommand(name: 'compact', source: SlashSource.agent),
      ];

      final rows = slashMenuRows(
        localization: localization,
        skills: skills,
        agent: duplicated,
        query: '',
      );

      expect([for (final r in rows) r.name].where((name) => name == 'run-tests'), hasLength(1));
      expect(rows.where((r) => r.name == 'run-tests').single.source, SlashSource.skill);
      expect(rows.where((r) => r.source == SlashSource.agent).map((r) => r.name), ['compact']);
    });

    test('without skills nothing changes for the app and the agent', () {
      final rows = slashMenuRows(
        localization: localization,
        skills: ChatSkills.empty,
        agent: agent,
        query: '',
      );

      expect(rows, slashSuggestions(appCommandsFor(null, localization), agent, ''));
    });
  });
}
