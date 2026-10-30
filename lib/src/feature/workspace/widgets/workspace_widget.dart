import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_chat_area.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_run_panel.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_sidebar.dart';

/// {@template workspace_widget}
/// Main window layout: projects sidebar, chat area and the run panel below it.
/// {@endtemplate}
class WorkspaceWidget extends StatefulWidget {
  /// {@macro workspace_widget}
  const WorkspaceWidget({super.key});

  @override
  State<WorkspaceWidget> createState() => _WorkspaceWidgetState();
}

class _WorkspaceWidgetState extends State<WorkspaceWidget> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(width: 260, child: WorkspaceSidebar()),
          VerticalDivider(width: 1, color: colorScheme.outlineVariant),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Expanded(child: WorkspaceChatArea()),
                Divider(height: 1, color: colorScheme.outlineVariant),
                const SizedBox(height: 220, child: WorkspaceRunPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
