import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
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
  const ChatItemView({required this.item, required this.onAnswerPermission, super.key});

  /// The item.
  final ChatItem item;

  /// Answers a permission card.
  final void Function(String requestId, String optionId) onAnswerPermission;

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
          constraints: const BoxConstraints(maxWidth: 640),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.large),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SelectableText(text),
                  for (final resource in resources)
                    Text('@${Uri.parse(resource).pathSegments.last}', style: muted),
                ],
              ),
            ),
          ),
        ),
      ),
      AgentMessageItem(:final text) => MarkdownBody(data: text, selectable: true),
      AgentThoughtItem(:final text) => Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.psychology_outlined, size: 18),
          title: Text(localization.thinking, style: muted),
          children: <Widget>[SelectableText(text, style: muted)],
        ),
      ),
      final ToolCallItem call => ToolCallCard(call: call),
      PlanItem(:final entries) => PlanCard(entries: entries),
      final PermissionItem permission => PermissionCard(
        item: permission,
        onAnswer: (optionId) => onAnswerPermission(permission.requestId, optionId),
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
