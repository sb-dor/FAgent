import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/diff_view.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';

/// {@template permission_card}
/// The agent asks before acting: what it wants to do (command or diff) and the
/// options it offers. The title tells the request type; once answered, the
/// card shows the decision.
///
/// Buttons: the primary allow (Enter), "always", the primary reject (Escape), the
/// other options, and "reject and say…" when [onRejectAndSay] is set.
/// {@endtemplate}
class PermissionCard extends StatelessWidget {
  /// {@macro permission_card}
  const PermissionCard({
    required this.item,
    required this.onAnswer,
    this.onRejectAndSay,
    super.key,
  });

  /// The request.
  final PermissionItem item;

  /// Called with the chosen `optionId`.
  final ValueChanged<String> onAnswer;

  /// Declines the request and lets the user say what to do instead; `null` hides the button.
  final VoidCallback? onRejectAndSay;

  String _title(GeneratedLocalization localization) => item.command != null
      ? localization.permissionRunCommand
      : item.diffs.isNotEmpty
      ? localization.permissionApplyEdits
      : item.title;

  /// Options in button order: primary allow, "always", primary reject, the rest.
  List<PermissionOptionView> get _ordered {
    final accept = item.acceptOption;
    final reject = item.rejectOption;
    int rank(PermissionOptionView o) => o == accept
        ? 0
        : o.kind == 'allow_always'
        ? 1
        : o == reject
        ? 2
        : 3;
    return item.options.toList()..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  Widget _button(PermissionOptionView option) {
    final label = option == item.acceptOption
        ? _WithHint(option.name, '↵', opacity: 0.7)
        : option == item.rejectOption
        ? _WithHint(option.name, 'Esc', opacity: 0.6)
        : Text(option.name);
    void onPressed() => onAnswer(option.optionId);
    return option == item.acceptOption
        ? FilledButton(onPressed: onPressed, child: label)
        : option == item.rejectOption || option.kind == 'allow_always'
        ? OutlinedButton(onPressed: onPressed, child: label)
        : TextButton(onPressed: onPressed, child: label);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final localization = Localization.of(context);
    final pending = item.state == PermissionState.pending;
    final command = item.command;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: pending ? colors.warnSoft : colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: pending ? colors.warn : colors.border),
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.pan_tool_outlined, size: 18, color: colors.warn),
                const SizedBox(width: 8),
                Expanded(child: Text(_title(localization), style: theme.textTheme.labelLarge)),
              ],
            ),
            if (command != null) ...<Widget>[
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText('\$ $command', style: AppText.mono(context, size: 13)),
                ),
              ),
            ],
            if (pending)
              for (final diff in item.diffs)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DiffView(path: diff.path, oldText: diff.oldText, newText: diff.newText),
                ),
            const SizedBox(height: 12),
            if (pending)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final option in _ordered) _button(option),
                  if (onRejectAndSay != null)
                    TextButton(
                      onPressed: onRejectAndSay,
                      style: TextButton.styleFrom(foregroundColor: colors.muted),
                      child: Text(localization.permissionRejectAndSay),
                    ),
                ],
              )
            else
              Text(
                _outcome(localization),
                style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
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

/// Button label with the key that answers from the keyboard, as a faded suffix.
class _WithHint extends StatelessWidget {
  const _WithHint(this.label, this.hint, {required this.opacity});

  final String label;
  final String hint;
  final double opacity;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Flexible(child: Text(label)),
      const SizedBox(width: 8),
      Opacity(
        opacity: opacity,
        child: Text(hint, style: const TextStyle(fontSize: 12)),
      ),
    ],
  );
}
