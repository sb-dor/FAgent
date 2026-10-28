import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/diff_view.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';

/// {@template permission_card}
/// The agent asks before acting: what it wants to do (command or diff) and the
/// options it offers. Once answered, shows the decision.
/// {@endtemplate}
class PermissionCard extends StatelessWidget {
  /// {@macro permission_card}
  const PermissionCard({required this.item, required this.onAnswer, super.key});

  /// The request.
  final PermissionItem item;

  /// Called with the chosen `optionId`.
  final ValueChanged<String> onAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localization = Localization.of(context);
    final pending = item.state == PermissionState.pending;
    final command = item.command;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: pending
          ? colors.tertiaryContainer.withValues(alpha: 0.45)
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: pending ? colors.tertiary : colors.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.pan_tool_outlined, size: 18, color: colors.tertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(localization.permissionTitle, style: theme.textTheme.labelLarge),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(item.title, style: theme.textTheme.bodyMedium),
            if (command != null) ...<Widget>[
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    '\$ $command',
                    style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'Menlo'),
                  ),
                ),
              ),
            ],
            if (pending)
              for (final diff in item.diffs)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DiffView(path: diff.path, oldText: diff.oldText, newText: diff.newText),
                ),
            const SizedBox(height: 10),
            if (pending)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final option in item.options)
                    if (option.allows)
                      FilledButton(
                        onPressed: () => onAnswer(option.optionId),
                        child: Text(option.name),
                      )
                    else
                      OutlinedButton(
                        onPressed: () => onAnswer(option.optionId),
                        child: Text(option.name),
                      ),
                ],
              )
            else
              Text(
                _outcome(localization),
                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  String _outcome(GeneratedLocalization localization) {
    switch (item.state) {
      case PermissionState.selected:
        final option = item.options.where((o) => o.optionId == item.selectedOptionId).firstOrNull;
        final verdict = (option?.allows ?? false)
            ? localization.permissionAllowed
            : localization.permissionRejected;
        return option == null ? verdict : '$verdict · ${option.name}';
      case PermissionState.cancelled:
        return localization.permissionCancelled;
      case PermissionState.stale:
        return localization.permissionStale;
      case PermissionState.pending:
        return '';
    }
  }
}
