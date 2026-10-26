import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';

/// {@template workspace_run_panel}
/// Devices, run, hot reload and logs. Filled in M2; empty state for now.
/// {@endtemplate}
class WorkspaceRunPanel extends StatelessWidget {
  /// {@macro workspace_run_panel}
  const WorkspaceRunPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localization = Localization.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(localization.runPanel, style: theme.textTheme.titleSmall),
          ),
          Expanded(
            child: Center(
              child: Text(
                localization.runPanelPlaceholder,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
