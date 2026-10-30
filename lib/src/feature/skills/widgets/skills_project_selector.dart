import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_config_widget.dart';

/// {@template skills_project_selector}
/// `Project: <name> ▾` in the title bar of the Skills screen: the project whose switches the
/// screen shows. It is hidden while there are no projects, and then every switch is global.
/// {@endtemplate}
class SkillsProjectSelector extends StatelessWidget {
  /// {@macro skills_project_selector}
  const SkillsProjectSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = SkillsConfigInhWidget.of(context);
    final localization = Localization.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        scope.view,
        // The scope reads the projects from this controller.
        scope.projectsListenable,
      ]),
      builder: (context, _) {
        final projects = scope.projects;
        if (projects.isEmpty) return const SizedBox.shrink();
        final project = scope.project;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: SelectorChip<int>(
            label: project == null
                ? localization.skillsChooseProject
                : localization.skillsProject(project.name),
            icon: Icons.folder_outlined,
            sections: <AppMenuSection<int>>[
              AppMenuSection<int>(
                items: <AppMenuItem<int>>[
                  for (final entry in projects)
                    AppMenuItem<int>(
                      value: entry.id,
                      title: entry.name,
                      subtitle: entry.path,
                      selected: entry.id == project?.id,
                    ),
                ],
              ),
            ],
            onSelected: scope.chooseProject,
          ),
        );
      },
    );
  }
}
