import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/sessions/controller/sessions_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/app_title_bar.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// {@template workspace_title_bar}
/// Title bar of the chat screen: the sidebar toggle, "chat · project" and the right pane toggle.
/// {@endtemplate}
class WorkspaceTitleBar extends StatelessWidget {
  /// {@macro workspace_title_bar}
  const WorkspaceTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = WorkspaceConfigInhWidget.of(context);
    final localization = Localization.of(context);
    return AppTitleBar(
      leading: <Widget>[
        TitleBarButton(
          icon: Icons.view_sidebar_outlined,
          tooltip: localization.toggleSidebar,
          onPressed: scope.toggleSidebar,
        ),
      ],
      title: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          scope.dataController,
          scope.projectsController,
          scope.sessionsController,
        ]),
        builder: (context, _) => Text(_title(context, scope)),
      ),
      trailing: <Widget>[
        TitleBarButton(
          icon: Icons.vertical_split_outlined,
          tooltip: localization.toggleRightPane,
          onPressed: () => scope.toggleRightPane(windowWidth: MediaQuery.sizeOf(context).width),
        ),
      ],
    );
  }

  String _title(BuildContext context, WorkspaceConfigWidgetState scope) {
    final localization = Localization.of(context);
    final project = scope.selectedProject;
    if (project == null) return localization.appTitle;
    final sessionId = scope.dataController.sessionId;
    if (sessionId == null) return project.name;
    final session = switch (scope.sessionsController.state) {
      Sessions$CompletedState(:final sessions) =>
        sessions
            .where((session) => session.id == sessionId && session.projectId == project.id)
            .firstOrNull,
      _ => null,
    };
    if (session == null) return project.name;
    final title = session.title.isEmpty ? localization.untitledChat : session.title;
    return '$title · ${project.name}';
  }
}
