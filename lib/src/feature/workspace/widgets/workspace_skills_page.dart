import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skill_card.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_config_widget.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_list.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_navigation.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_project_selector.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_page_scaffold.dart';

/// Width of the list of skills and rules.
const double _kListWidth = 320;

/// {@template workspace_skills_page}
/// The Skills and rules screen: sections and sources in the navigation, the list of items and the
/// open item.
/// {@endtemplate}
class WorkspaceSkillsPage extends StatelessWidget {
  /// {@macro workspace_skills_page}
  const WorkspaceSkillsPage({super.key});

  @override
  Widget build(BuildContext context) => const SkillsConfigWidget(child: _SkillsScreen());
}

class _SkillsScreen extends StatelessWidget {
  const _SkillsScreen();

  @override
  Widget build(BuildContext context) {
    final scope = SkillsConfigInhWidget.of(context);
    final localization = Localization.of(context);
    final sections = <(String id, IconData icon, String label)>[
      (KnowledgeKind.skill.name, Icons.auto_awesome_outlined, localization.skills),
      (KnowledgeKind.rule.name, Icons.rule_outlined, localization.rules),
    ];
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[scope.view, scope.library]),
      builder: (context, _) {
        final view = scope.view;
        final library = scope.library.library;
        return WorkspacePageScaffold(
          title: localization.skillsAndRules,
          sections: sections,
          // A source filter replaces the section as the highlighted item of the navigation.
          selected: view.source == null ? view.kind.name : '',
          onSelect: (id) => scope.chooseKind(KnowledgeKind.values.byName(id)),
          sectionBadges: <String, String>{
            KnowledgeKind.skill.name: '${library.skills.length}',
            KnowledgeKind.rule.name: '${library.rules.length}',
          },
          navigationFooter: const SkillsNavigation(),
          actions: const <Widget>[SkillsProjectSelector()],
          fill: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(width: _kListWidth, child: SkillsList()),
              VerticalDivider(width: 1, color: context.colors.border),
              const Expanded(child: SkillCard()),
            ],
          ),
        );
      },
    );
  }
}
