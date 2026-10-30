import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_config_widget.dart';

/// {@template skill_scope}
/// Where [item] is on: a switch for all projects, a chip for every project that differs from it
/// (its ✕ makes the project follow the switch again) and a menu to add such a project.
///
/// An item of a project has no global switch, only one for the project of the screen.
/// {@endtemplate}
class SkillScope extends StatelessWidget {
  /// {@macro skill_scope}
  const SkillScope({required this.item, super.key});

  /// The skill or rule.
  final KnowledgeItem item;

  @override
  Widget build(BuildContext context) {
    final scope = SkillsConfigInhWidget.of(context);
    final localization = Localization.of(context);
    return ListenableBuilder(
      listenable: scope.projectsListenable,
      builder: (context, _) {
        if (item.source == SkillSource.project) {
          final name = scope.project?.name;
          return _SwitchLabel(
            key: const ValueKey<String>('skill-project-switch'),
            label: name == null
                ? localization.skillEnabled
                : localization.skillEnabledInProject(name),
            value: item.enabled,
            onChanged: (enabled) => scope.actions.setEnabled(
              item.id,
              enabled: enabled,
              projectId: scope.view.projectId,
            ),
          );
        }
        final byId = {for (final project in scope.projects) project.id: project};
        final exceptions = <Project>[for (final id in item.exceptions) ?byId[id]]
          ..sort((a, b) => a.name.compareTo(b.name));
        final available = [
          for (final project in scope.projects)
            if (!item.exceptions.contains(project.id)) project,
        ];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _SwitchLabel(
              key: const ValueKey<String>('skill-global-switch'),
              label: localization.skillAllProjects,
              value: item.enabledGlobally,
              onChanged: (enabled) => scope.actions.setEnabled(item.id, enabled: enabled),
            ),
            for (final project in exceptions)
              _ExceptionChip(
                name: project.name,
                // Where the item differs from the switch it is on when the switch is off.
                enabledThere: !item.enabledGlobally,
                onClear: () => scope.actions.clearException(item.id, project.id),
              ),
            if (available.isNotEmpty)
              SelectorChip<int>(
                label: localization.skillAddException,
                sections: <AppMenuSection<int>>[
                  AppMenuSection<int>(
                    items: <AppMenuItem<int>>[
                      for (final project in available)
                        AppMenuItem<int>(
                          value: project.id,
                          title: project.name,
                          subtitle: project.path,
                        ),
                    ],
                  ),
                ],
                onSelected: (projectId) => scope.actions.setEnabled(
                  item.id,
                  enabled: !item.enabledGlobally,
                  projectId: projectId,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A [Switch] with its label, which also toggles it.
class _SwitchLabel extends StatelessWidget {
  const _SwitchLabel({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.small),
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The label is the tap target too, so the switch itself ignores taps.
          IgnorePointer(
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(width: 4),
        ],
      ),
    ),
  );
}

/// `<project> ✕`: the project differs from the global switch.
class _ExceptionChip extends StatelessWidget {
  const _ExceptionChip({required this.name, required this.enabledThere, required this.onClear});

  final String name;

  /// Whether the item is on in this project (and off elsewhere).
  final bool enabledThere;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = enabledThere ? colors.accent : colors.muted;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: enabledThere ? colors.accentSoft : colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(enabledThere ? Icons.check : Icons.block, size: 12, color: foreground),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(color: foreground),
              ),
            ),
            IconButton(
              tooltip: Localization.of(context).skillClearException,
              onPressed: onClear,
              icon: Icon(Icons.close, size: 12, color: foreground),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            ),
          ],
        ),
      ),
    );
  }
}
