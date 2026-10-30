import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/status.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_sidebar_row.dart';

/// Name of the agent [id] as the user knows it; unknown ids are shown as they are.
String agentDisplayName(String id) => switch (id) {
  'claude' => 'Claude Code',
  _ => id,
};

/// {@template workspace_sidebar_footer}
/// The bottom of the sidebar: the Skills and Settings screens and the default agent.
/// {@endtemplate}
class WorkspaceSidebarFooter extends StatelessWidget {
  /// {@macro workspace_sidebar_footer}
  const WorkspaceSidebarFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = WorkspaceConfigInhWidget.of(context);
    final localization = Localization.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        WorkspaceSidebarRow(
          icon: Icons.extension_outlined,
          label: localization.skills,
          onTap: () => scope.dataController.openView(WorkspaceView.skills),
        ),
        WorkspaceSidebarRow(
          icon: Icons.settings_outlined,
          label: localization.settings,
          onTap: () => scope.dataController.openView(WorkspaceView.settings),
        ),
        ListenableBuilder(
          listenable: scope.settingsController,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: <Widget>[
                // Whether the agent is signed in arrives with the Agents settings.
                const StatusDot(tone: AppStatusTone.none),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    agentDisplayName(scope.settingsController.settings.defaultAgentId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall!
                        .copyWith(color: context.colors.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
