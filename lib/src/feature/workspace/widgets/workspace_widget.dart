import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/constant/window_constants.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_chat_area.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_right_pane.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_settings_page.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_shortcuts.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_sidebar.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_skills_page.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_title_bar.dart';

/// {@template workspace_widget}
/// Main window layout: the title bar over [sidebar | chat | right pane], or over the Skills or
/// Settings screen.
/// {@endtemplate}
class WorkspaceWidget extends StatefulWidget {
  /// {@macro workspace_widget}
  const WorkspaceWidget({super.key});

  @override
  State<WorkspaceWidget> createState() => _WorkspaceWidgetState();
}

class _WorkspaceWidgetState extends State<WorkspaceWidget> {
  late final _scope = WorkspaceConfigInhWidget.of(context);

  /// The chat layout stays mounted under Skills and Settings, so the composer draft, scroll
  /// position and the like survive a visit there; it is hidden, silent and cannot take focus.
  @override
  Widget build(BuildContext context) => Scaffold(
    body: WorkspaceShortcuts(
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          _scope.dataController,
          _scope.settingsController,
        ]),
        builder: (context, _) {
          final view = _scope.dataController.view;
          final chat = view == WorkspaceView.chat;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Offstage(
                offstage: !chat,
                child: TickerMode(
                  enabled: chat,
                  child: ExcludeFocus(excluding: !chat, child: _buildChat(context)),
                ),
              ),
              switch (view) {
                WorkspaceView.chat => const SizedBox.shrink(),
                WorkspaceView.skills => const WorkspaceSkillsPage(),
                WorkspaceView.settings => const WorkspaceSettingsPage(),
              },
            ],
          );
        },
      ),
    ),
  );

  Widget _buildChat(BuildContext context) {
    final settings = _scope.settingsController.settings;
    final rightPaneVisible =
        settings.rightPaneVisible ?? MediaQuery.sizeOf(context).width >= kWideWindowWidth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const WorkspaceTitleBar(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (settings.sidebarVisible) ...<Widget>[
                const SizedBox(width: kSidebarWidth, child: WorkspaceSidebar()),
                VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
              ],
              const Expanded(child: WorkspaceChatArea()),
              if (rightPaneVisible) const WorkspaceRightPane(),
            ],
          ),
        ),
      ],
    );
  }
}
