import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/constant/window_constants.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:window_manager/window_manager.dart';

/// {@template workspace_chat_area}
/// Chat with the agent. Filled in M1; empty state for now.
/// {@endtemplate}
class WorkspaceChatArea extends StatelessWidget {
  /// {@macro workspace_chat_area}
  const WorkspaceChatArea({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const DragToMoveArea(child: SizedBox(height: kWindowTitleBarHeight)),
        Expanded(
          child: Center(
            child: Text(
              Localization.of(context).chatPlaceholder,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}
