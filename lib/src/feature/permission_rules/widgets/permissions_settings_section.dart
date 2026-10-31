import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/compact_button.dart';
import 'package:flutter_code_agent/src/common/widget/empty_state.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/settings_row.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/controller/permission_rules_controller.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/widgets/permission_rules_config_widget.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';

/// {@template permissions_settings_section}
/// The "Permissions" section of Settings: for every project, a card with the rules "Always allow
/// in this project" saved for it, each with a button that removes it.
///
/// A project whose `settings.local.json` cannot be read says so in its card. The projects without
/// rules are counted in one line at the end; without any project there is an [EmptyState].
/// Removing asks nothing: the rule can be given again in a chat.
/// {@endtemplate}
class PermissionsSettingsSection extends StatelessWidget {
  /// {@macro permissions_settings_section}
  const PermissionsSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = PermissionRulesConfigInhWidget.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[scope.rules, scope.projectsListenable]),
      builder: (context, _) {
        final localization = Localization.of(context);
        final colors = context.colors;
        final projects = scope.projects;
        final state = scope.rules.state;
        final loaded = switch (state) {
          PermissionRules$CompletedState(:final rules) => rules,
          _ => null,
        };
        if (projects != null && projects.isEmpty) {
          return EmptyState(
            icon: Icons.shield_outlined,
            title: localization.permissionsNoProjects,
            message: localization.permissionsNoProjectsHint,
          );
        }
        if (projects == null || loaded == null) {
          return Text(
            localization.permissionsLoading,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.muted),
          );
        }
        final withoutRules = <Project>[];
        final cards = <Widget>[];
        for (final project in projects) {
          switch (loaded[project.id]) {
            case ProjectRules$Rules(:final rules) when rules.isEmpty:
              withoutRules.add(project);
            case ProjectRules$Rules(:final rules):
              cards.add(_ProjectCard(project: project, rules: rules));
            case ProjectRules$Unreadable():
              cards.add(_ProjectCard(project: project));
            case null:
              break;
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final card in cards) ...<Widget>[card, const SizedBox(height: 16)],
            if (withoutRules.isNotEmpty) ...<Widget>[
              Text(
                localization.permissionsNoRules(withoutRules.length),
                style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.muted),
              ),
              const SizedBox(height: 12),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: CompactButton(
                label: localization.permissionsRefresh,
                icon: Icons.refresh,
                onPressed: scope.refresh,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A card of one project: its name and path, then its [rules], or the line that its settings file
/// could not be read when [rules] is `null`.
class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, this.rules});

  final Project project;
  final List<String>? rules;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final rules = this.rules;
    return SettingsCard(
      key: ValueKey<String>('permissions-card-${project.id}'),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                project.name,
                style: textTheme.bodyMedium!.copyWith(
                  color: colors.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                project.path,
                style: AppText.mono(context, size: 12).copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
        if (rules == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              localization.permissionsUnreadable,
              key: ValueKey<String>('permissions-unreadable-${project.id}'),
              style: textTheme.bodySmall!.copyWith(color: colors.danger),
            ),
          )
        else
          for (final rule in rules) _RuleRow(project: project, rule: rule),
      ],
    );
  }
}

/// One saved rule, in monospace, with the button that removes it.
class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.project, required this.rule});

  final Project project;
  final String rule;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scope = PermissionRulesConfigInhWidget.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              rule,
              key: ValueKey<String>('permissions-rule-${project.id}-$rule'),
              style: AppText.mono(context, size: 12).copyWith(color: colors.text),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: ValueKey<String>('permissions-remove-${project.id}-$rule'),
            tooltip: Localization.of(context).permissionsRemoveRule,
            icon: const Icon(Icons.delete_outline, size: 18),
            color: colors.muted,
            visualDensity: VisualDensity.compact,
            onPressed: () => scope.rules.remove(project, rule),
          ),
        ],
      ),
    );
  }
}
