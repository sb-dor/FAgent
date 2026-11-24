import 'package:flutter/material.dart';
import 'package:flutter_code_agent/_core/localization/localization.dart';
import 'package:flutter_code_agent/project_creation/widgets/creation_dialog.dart';
import 'package:flutter_code_agent/project_creation/widgets/new_project_form.dart';

/// {@template new_project_dialog}
/// The New project wizard: a [CreationDialog] that asks for the project ([NewProjectForm]) and,
/// once the creation has started, shows how it goes.
///
/// It reads the window's `ProjectCreationController` from the workspace, so it has to be shown
/// under a `WorkspaceConfigInhWidget` (`WorkspaceConfigWidgetState.openNewProject` does that).
/// Closing it does not stop a creation: the controller lives as long as the window, and the
/// dialog opens on the progress again while the creation runs or waits for its "Close" or
/// "Open project". "Open project" closes the dialog and opens the created project in the
/// workspace, with a chat if the request asked for one.
/// {@endtemplate}
class NewProjectDialog extends StatelessWidget {
  /// {@macro new_project_dialog}
  const NewProjectDialog({super.key});

  @override
  Widget build(BuildContext context) =>
      CreationDialog(title: Localization.of(context).newProjectTitle, form: const NewProjectForm());
}
