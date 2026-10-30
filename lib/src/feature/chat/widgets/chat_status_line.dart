import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/constant/chat_constants.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';

/// {@template chat_status_line}
/// What the agent is doing right now (nothing when it is idle).
/// {@endtemplate}
class ChatStatusLine extends StatelessWidget {
  /// {@macro chat_status_line}
  const ChatStatusLine({required this.status, this.preparing = false, super.key});

  /// Session status.
  final SessionStatus status;

  /// A running turn has not sent its prompt yet.
  final bool preparing;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final text = switch (status) {
      SessionStatus.starting => localization.statusStarting,
      SessionStatus.loading => localization.statusLoading,
      SessionStatus.creating => localization.statusCreating,
      SessionStatus.running when preparing => localization.preparingTurn,
      SessionStatus.running => localization.statusRunning,
      SessionStatus.awaitingPermission => localization.statusAwaitingPermission,
      SessionStatus.cancelling => localization.statusCancelling,
      _ => null,
    };
    if (text == null) return const SizedBox(height: 4);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kChatColumnWidth),
          child: Row(
            children: <Widget>[
              if (status != SessionStatus.awaitingPermission)
                const SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.pan_tool_outlined, size: 14, color: context.colors.warn),
              const SizedBox(width: 8),
              Text(text, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
