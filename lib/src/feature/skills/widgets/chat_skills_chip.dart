import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_code_agent/src/feature/skills/models/chat_skills.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';

/// {@template chat_skills_chip}
/// The 🧩 chip of the composer: how many skills are on for this chat. Its menu lists the skills
/// that are on for the chat's project, each with a checkbox that turns the skill off (or on again)
/// for this chat only, and leads to the skill library.
///
/// A project's own skill is read by the agent when the chat starts, so its row says the change
/// applies when the chat is reopened. Nothing is shown while the project's skills are not known.
/// {@endtemplate}
class ChatSkillsChip extends StatelessWidget {
  /// {@macro chat_skills_chip}
  const ChatSkillsChip({
    required this.skills,
    required this.onOpenLibrary,
    this.chatStates = const <String, bool>{},
    this.onToggle,
    super.key,
  });

  /// The skills of the chat's project.
  final ChatSkills skills;

  /// What this chat changed against its project, by skill id (see `IChatSkillsRepository`).
  final Map<String, bool> chatStates;

  /// A checkbox was ticked or cleared: the [skill] is to be [enabled] for this chat. `null` leaves
  /// the rows without effect.
  final void Function(ChatSkill skill, {required bool enabled})? onToggle;

  /// "Open the skill library →" was chosen.
  final VoidCallback onOpenLibrary;

  bool _isOn(ChatSkill skill) => chatStates[skill.id] ?? skill.enabled;

  @override
  Widget build(BuildContext context) {
    final project = skills.projectName;
    if (project == null) return const SizedBox.shrink();
    final localization = Localization.of(context);
    // The choice is among the skills the project has on.
    final offered = <ChatSkill>[
      for (final skill in skills.skills)
        if (skill.enabled) skill,
    ];
    return SelectorChip<String>(
      label: '${offered.where(_isOn).length}',
      icon: Icons.extension_outlined,
      tooltip: localization.chatSkillsTooltip,
      menuWidth: 360,
      onSelected: (id) {
        for (final skill in offered) {
          if (skill.id == id) onToggle?.call(skill, enabled: !_isOn(skill));
        }
      },
      sections: <AppMenuSection<String>>[
        AppMenuSection<String>(
          title: localization.chatSkillsEnabledFor(project),
          items: <AppMenuItem<String>>[
            for (final skill in offered)
              AppMenuItem<String>(
                value: skill.id,
                title: skill.name,
                subtitle: skill.source == SkillSource.project
                    ? localization.chatSkillsAppliesOnReopen
                    : skill.description.isEmpty
                    ? null
                    : skill.description,
                icon: _isOn(skill) ? Icons.check_box : Icons.check_box_outline_blank,
                mono: true,
              ),
            if (offered.isEmpty)
              AppMenuItem<String>(value: '', title: localization.chatSkillsNone, enabled: false),
          ],
        ),
      ],
      footerBuilder: (context, close) => _Footer(
        onOpenLibrary: () {
          close(null);
          onOpenLibrary();
        },
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onOpenLibrary});

  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final theme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.small),
          onTap: onOpenLibrary,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text(
              localization.chatSkillsOpenLibrary,
              style: theme.bodyMedium!.copyWith(color: colors.accent),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Text(
            localization.chatSkillsNote,
            style: theme.bodySmall!.copyWith(color: colors.muted),
          ),
        ),
      ],
    );
  }
}
