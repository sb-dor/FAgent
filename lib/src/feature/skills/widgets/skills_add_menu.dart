import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_config_widget.dart';

enum _AddAction { create, folder, git, generate }

/// {@template skills_add_menu}
/// `＋ Add ▾` over the list: create an item in the open section, import a skill folder, add one
/// from a git repository (arrives with M3), or ask an agent to write a skill.
/// {@endtemplate}
class SkillsAddMenu extends StatelessWidget {
  /// {@macro skills_add_menu}
  const SkillsAddMenu({super.key});

  Future<void> _open(BuildContext context) async {
    final scope = SkillsConfigInhWidget.of(context);
    final localization = Localization.of(context);
    final box = context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final skills = scope.view.kind == KnowledgeKind.skill;
    final action = await showAppMenu<_AddAction>(
      context: context,
      anchor: anchor,
      width: 260,
      sections: <AppMenuSection<_AddAction>>[
        AppMenuSection<_AddAction>(
          items: <AppMenuItem<_AddAction>>[
            AppMenuItem<_AddAction>(
              value: _AddAction.create,
              title: localization.skillsAddCreate,
              icon: Icons.edit_outlined,
            ),
            if (skills)
              AppMenuItem<_AddAction>(
                value: _AddAction.folder,
                title: localization.skillsAddFolder,
                icon: Icons.folder_open_outlined,
              ),
            AppMenuItem<_AddAction>(
              value: _AddAction.git,
              title: localization.skillsAddGit,
              icon: Icons.call_split,
              badge: const PreviewBadge(),
            ),
            AppMenuItem<_AddAction>(
              value: _AddAction.generate,
              title: localization.skillsAddGenerate,
              icon: Icons.auto_awesome_outlined,
              // The agent writes into the project, so there has to be one.
              enabled: scope.view.projectId != null,
            ),
          ],
        ),
      ],
    );
    switch (action) {
      case _AddAction.create:
        await scope.createItem();
      case _AddAction.folder:
        await scope.importFromFolder();
      case _AddAction.git:
        scope.showComingSoon();
      case _AddAction.generate:
        scope.generateWithAgent();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    return FilledButton(
      onPressed: () => _open(context),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.only(left: 12, right: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: Theme.of(context).textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w500),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(localization.skillsAdd),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    );
  }
}
