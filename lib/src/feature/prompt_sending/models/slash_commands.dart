import 'package:flutter_code_agent/src/feature/prompt_sending/models/slash_command.dart';
import 'package:flutter_code_agent/src/feature/skills/models/chat_skills.dart';

final RegExp _whitespace = RegExp(r'\s');

/// The skills of the chat's project as `/` commands: only the ones that are on. Only a project
/// skill can be run now ([ChatSkill.invocable]); the others are dimmed with `M3`. Of equal names
/// the first one wins, and a name with whitespace is skipped.
List<SlashCommand> skillCommands(ChatSkills skills) {
  final seen = <String>{};
  return <SlashCommand>[
    for (final skill in skills.skills)
      if (skill.enabled && !skill.name.contains(_whitespace) && seen.add(skill.name))
        SlashCommand(
          name: skill.name,
          source: SlashSource.skill,
          description: skill.description.isEmpty ? null : skill.description,
          enabled: skill.invocable,
          hint: skill.invocable ? null : 'M3',
        ),
  ];
}

/// What the `/` menu of a chat shows for [query]: its project [skills], the app's commands and the
/// [agent]'s.
List<SlashCommand> slashMenuRows({
  required ChatSkills skills,
  required List<SlashCommand> agent,
  required String query,
}) => slashSuggestions(appCommands, agent, query, skills: skillCommands(skills));
