import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/project_rules/models/project_rule.dart';

/// {@template project_rules_dialog}
/// Offers the app's built-in [rules] to a project: one checkbox per rule, its name and description,
/// the ones that are on checked. **Add** returns the checked rules, **Not now** returns `null`.
/// {@endtemplate}
class ProjectRulesDialog extends StatefulWidget {
  /// {@macro project_rules_dialog}
  const ProjectRulesDialog({required this.rules, super.key});

  /// Shows the dialog; the rules to add, or `null` when the user declined.
  static Future<List<ProjectRule>?> show(BuildContext context, List<ProjectRule> rules) =>
      showDialog<List<ProjectRule>>(
        context: context,
        builder: (context) => ProjectRulesDialog(rules: rules),
      );

  /// The built-in rules, in library order.
  final List<ProjectRule> rules;

  @override
  State<ProjectRulesDialog> createState() => _ProjectRulesDialogState();
}

class _ProjectRulesDialogState extends State<ProjectRulesDialog> {
  late final Set<String> _checked = <String>{
    for (final rule in widget.rules)
      if (rule.enabled) rule.id,
  };

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final chosen = <ProjectRule>[
      for (final rule in widget.rules)
        if (_checked.contains(rule.id)) rule,
    ];
    return AlertDialog(
      title: Text(localization.projectRulesTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(localization.projectRulesExplain, style: textTheme.bodyMedium),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final rule in widget.rules)
                      CheckboxListTile(
                        value: _checked.contains(rule.id),
                        onChanged: (value) => setState(
                          () => (value ?? false) ? _checked.add(rule.id) : _checked.remove(rule.id),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(rule.name),
                        subtitle: Text(
                          rule.description,
                          style: textTheme.bodySmall?.copyWith(color: colors.muted),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localization.projectRulesNotNow),
        ),
        FilledButton(
          onPressed: chosen.isEmpty ? null : () => Navigator.of(context).pop(chosen),
          child: Text(localization.projectRulesAdd),
        ),
      ],
    );
  }
}
