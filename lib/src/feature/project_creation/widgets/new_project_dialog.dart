import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/project_creation/controller/project_creation_controller.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/new_project_form.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// {@template new_project_dialog}
/// The New project wizard: a 560 px dialog that asks for the project ([NewProjectForm]) and, once
/// the creation has started, shows how it goes.
///
/// It reads the window's [ProjectCreationController] from the workspace, so it has to be shown
/// under a [WorkspaceConfigInhWidget] (`WorkspaceConfigWidgetState.openNewProject` does that).
/// Closing it does not stop a creation: the controller lives as long as the window.
/// {@endtemplate}
class NewProjectDialog extends StatelessWidget {
  /// {@macro new_project_dialog}
  const NewProjectDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final creation = WorkspaceConfigInhWidget.of(context).projectCreation;
    return Actions(
      // The dialog is not dismissible by its barrier, so Esc is handled here.
      actions: <Type, Action<Intent>>{
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            Navigator.of(context).pop();
            return null;
          },
        ),
      },
      child: Dialog(
        backgroundColor: colors.bg,
        surfaceTintColor: colors.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        localization.newProjectTitle,
                        style: Theme.of(context).textTheme.titleMedium!
                            .copyWith(color: colors.text, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: localization.close,
                      icon: Icon(Icons.close, size: 18, color: colors.muted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListenableBuilder(
                  listenable: creation,
                  builder: (context, _) => switch (creation.state) {
                    ProjectCreation$IdleState() => const NewProjectForm(),
                    // Task 3 replaces this with the progress of the steps.
                    ProjectCreation$RunningState(:final steps) ||
                    ProjectCreation$CompletedState(:final steps) ||
                    ProjectCreation$FailedState(:final steps) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      child: Text(
                        localization.newProjectStepsDone(
                          steps.where((step) => step.status == CreationStepStatus.done).length,
                          steps.length,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: colors.text),
                      ),
                    ),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
