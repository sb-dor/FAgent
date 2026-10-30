import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/mention_spans.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/expandable_row.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/plan_card.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/tool_call_card.dart';
import 'package:flutter_code_agent/src/feature/permission_request/widgets/permission_card.dart';
import 'package:flutter_code_agent/src/feature/turn_files/widgets/turn_files_card.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// {@template chat_item_view}
/// Renders one feed item.
/// {@endtemplate}
class ChatItemView extends StatelessWidget {
  /// {@macro chat_item_view}
  const ChatItemView({
    required this.item,
    required this.onAnswerPermission,
    this.onRejectAndSay,
    this.projectRoot,
    this.keyboardTarget = false,
    super.key,
  });

  /// The item.
  final ChatItem item;

  /// Answers a permission card.
  final void Function(String requestId, String optionId) onAnswerPermission;

  /// Declines a permission card and lets the user say why; `null` hides the button.
  final void Function(PermissionItem item)? onRejectAndSay;

  /// The chat's project folder; tool paths inside it are shown relative to it.
  final String? projectRoot;

  /// This permission card is the one Enter and Esc answer (shows the key hints).
  final bool keyboardTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localization = Localization.of(context);
    final colors = context.colors;
    final muted = theme.textTheme.bodySmall?.copyWith(color: colors.muted);
    return switch (item) {
      UserMessageItem(:final text, :final resources) => Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(AppRadius.large),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SelectableText.rich(
                TextSpan(
                  children: mentionSpans(
                    text,
                    resources,
                    pill: AppText.mono(
                      context,
                      size: 13,
                    ).copyWith(color: colors.accent, backgroundColor: colors.accentSoft),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      AgentMessageItem(:final text) => MarkdownBody(data: text, selectable: true),
      AgentThoughtItem(:final text, :final duration) => ExpandableRow(
        bordered: false,
        header: Row(
          children: <Widget>[
            Icon(Icons.psychology_outlined, size: 16, color: colors.muted),
            const SizedBox(width: 8),
            Text(
              duration != null && duration.inSeconds >= 1
                  ? localization.thinkingFor(duration.inSeconds)
                  : localization.thinking,
              style: muted,
            ),
          ],
        ),
        body: text.isEmpty ? null : SelectableText(text, style: muted),
      ),
      final ToolCallItem call => ToolCallCard(call: call, projectRoot: projectRoot),
      PlanItem(:final entries) => PlanCard(entries: entries),
      final PermissionItem permission => PermissionCard(
        item: permission,
        keyboardTarget: keyboardTarget,
        onAnswer: (optionId) => onAnswerPermission(permission.requestId, optionId),
        onRejectAndSay: onRejectAndSay == null ? null : () => onRejectAndSay!(permission),
      ),
      TurnFilesItem(:final files) => TurnFilesCard(files: files),
      TurnEndItem(:final stopReason) => Center(
        child: Text(switch (stopReason) {
          'cancelled' => localization.turnCancelled,
          'refusal' => localization.turnRefused,
          _ => localization.turnLimit,
        }, style: muted),
      ),
      SystemItem(:final type, :final message) => Row(
        children: <Widget>[
          Icon(
            type == 'error' ? Icons.error_outline : Icons.info_outline,
            size: 16,
            color: type == 'error' ? colors.danger : colors.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              type == 'context_lost' ? localization.contextLost : message ?? type,
              style: muted,
            ),
          ),
        ],
      ),
      UnknownItem(:final kind) => Text(localization.unknownEvent(kind), style: muted),
    };
  }
}
