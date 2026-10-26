import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/constant/window_constants.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:window_manager/window_manager.dart';

/// {@template workspace_sidebar}
/// Projects and their sessions. Filled in M1; empty state for now.
/// {@endtemplate}
class WorkspaceSidebar extends StatelessWidget {
  /// {@macro workspace_sidebar}
  const WorkspaceSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localization = Localization.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const DragToMoveArea(child: SizedBox(height: kWindowTitleBarHeight)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(localization.projects, style: theme.textTheme.titleSmall)),
                IconButton(
                  tooltip: localization.openProject,
                  icon: const Icon(Icons.add),
                  onPressed: null,
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                localization.noProjectsYet,
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
