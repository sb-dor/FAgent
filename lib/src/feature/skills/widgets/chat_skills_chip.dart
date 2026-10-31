import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_code_agent/src/feature/skills/models/chat_skills.dart';

/// {@template chat_skills_chip}
/// The 🧩 chip of the composer: how many skills are on for the chat's project. Its menu lists the
/// skills that are on, then the ones that are off (dimmed), and leads to the skill library.
///
/// The rows do not switch anything: choosing skills for a single chat and handing them to the agent
/// arrive with milestone M3, and the menu says so. Nothing is shown while the project's skills are
/// not known.
/// {@endtemplate}
class ChatSkillsChip extends StatelessWidget {
  /// {@macro chat_skills_chip}
  const ChatSkillsChip({required this.skills, required this.onOpenLibrary, super.key});

  /// The skills of the chat's project.
  final ChatSkills skills;

  /// "Open the skill library →" was chosen.
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final project = skills.projectName;
    if (project == null) return const SizedBox.shrink();
    final localization = Localization.of(context);
    final all = skills.skills;
    final ordered = <ChatSkill>[
      ...all.where((skill) => skill.enabled),
      ...all.where((skill) => !skill.enabled),
    ];
    return SelectorChip<String>(
      label: '${skills.enabledCount}',
      icon: Icons.extension_outlined,
      tooltip: localization.chatSkillsTooltip,
      menuWidth: 360,
      sections: <AppMenuSection<String>>[
        AppMenuSection<String>(
          title: localization.chatSkillsEnabledFor(project),
          items: <AppMenuItem<String>>[
            for (final skill in ordered)
              AppMenuItem<String>(
                value: skill.id,
                title: skill.name,
                subtitle: skill.description.isEmpty ? null : skill.description,
                icon: Icons.extension_outlined,
                mono: true,
                enabled: skill.enabled,
              ),
            if (ordered.isEmpty)
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const PreviewBadge(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  localization.chatSkillsNote,
                  style: theme.bodySmall!.copyWith(color: colors.muted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
