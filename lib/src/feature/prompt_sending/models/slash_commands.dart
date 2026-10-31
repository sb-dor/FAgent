import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/run_mentions.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/slash_command.dart';
import 'package:flutter_code_agent/src/feature/skills/models/chat_skills.dart';

final RegExp _whitespace = RegExp(r'\s');

/// The skills of the chat's project as `/` commands: only the ones that are on. Only a project
/// skill can be run now ([ChatSkill.invocable]); the others are dimmed with `Coming in M3`. Of equal names
/// the first one wins, and a name with whitespace is skipped.
List<SlashCommand> skillCommands(ChatSkills skills, GeneratedLocalization localization) {
  final seen = <String>{};
  return <SlashCommand>[
    for (final skill in skills.skills)
      if (skill.enabled && !skill.name.contains(_whitespace) && seen.add(skill.name))
        SlashCommand(
          name: skill.name,
          source: SlashSource.skill,
          description: skill.description.isEmpty ? null : skill.description,
          enabled: skill.invocable,
          hint: skill.invocable ? null : localization.comingInMilestone('M3'),
        ),
  ];
}

/// The commands of the app: `run` works when [run] says the app can start, `reload` and `restart`
/// when it runs, `screenshot` when it runs in debug. A command that does not work says why
/// (`hint`): `run` asks for a device, the others for a running app. Without [run] none works.
List<SlashCommand> appCommandsFor(RunMentions? run, GeneratedLocalization localization) {
  SlashCommand command(String name, {required bool enabled, required String whyNot}) =>
      SlashCommand(
        name: name,
        source: SlashSource.app,
        enabled: enabled,
        hint: enabled ? null : whyNot,
      );
  final needsRun = localization.runCommandNeedsRun;
  final canReload = run?.canReload ?? false;
  return <SlashCommand>[
    command('run', enabled: run?.canStart ?? false, whyNot: localization.runCommandNeedsDevice),
    command('reload', enabled: canReload, whyNot: needsRun),
    command('restart', enabled: canReload, whyNot: needsRun),
    command('screenshot', enabled: run?.canScreenshot ?? false, whyNot: needsRun),
  ];
}

/// What the `/` menu of a chat shows for [query]: its project [skills], the app's commands (as [run]
/// lets them work) and the [agent]'s.
///
/// The agent lists the project's skills among its commands (claude-agent-acp does), so an agent
/// command named like a skill is dropped: the skill row is the one that stays.
List<SlashCommand> slashMenuRows({
  required GeneratedLocalization localization,
  required ChatSkills skills,
  required List<SlashCommand> agent,
  required String query,
  RunMentions? run,
}) {
  final skillRows = skillCommands(skills, localization);
  final skillNames = {for (final skill in skillRows) skill.name};
  return slashSuggestions(
    appCommandsFor(run, localization),
    [
      for (final command in agent)
        if (!skillNames.contains(command.name)) command,
    ],
    query,
    skills: skillRows,
  );
}
