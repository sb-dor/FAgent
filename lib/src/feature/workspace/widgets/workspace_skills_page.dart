import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_page_scaffold.dart';

/// {@template workspace_skills_page}
/// The Skills and rules screen. Sections are placeholders until milestone M3.
/// {@endtemplate}
class WorkspaceSkillsPage extends StatelessWidget {
  /// {@macro workspace_skills_page}
  const WorkspaceSkillsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = WorkspaceConfigInhWidget.of(context).dataController;
    final localization = Localization.of(context);
    final sections = <(String id, IconData icon, String label)>[
      ('skills', Icons.auto_awesome_outlined, localization.skills),
      ('rules', Icons.rule_outlined, localization.rules),
    ];
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final selected = sections.firstWhere(
          (section) => section.$1 == data.section,
          orElse: () => sections.first,
        );
        return WorkspacePageScaffold(
          title: localization.skillsAndRules,
          sections: sections,
          selected: selected.$1,
          onSelect: (id) => data.openView(WorkspaceView.skills, section: id),
          child: SectionPlaceholder(icon: selected.$2, title: selected.$3, milestone: 'M3'),
        );
      },
    );
  }
}
