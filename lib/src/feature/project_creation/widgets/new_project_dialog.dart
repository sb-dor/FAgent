import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/project_creation/controller/project_creation_controller.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/creation_progress.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/new_project_form.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/new_project_header.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// {@template new_project_dialog}
/// The New project wizard: a 560 px dialog that asks for the project ([NewProjectForm]) and, once
/// the creation has started, shows how it goes ([CreationProgress]).
///
/// It reads the window's [ProjectCreationController] from the workspace, so it has to be shown
/// under a [WorkspaceConfigInhWidget] (`WorkspaceConfigWidgetState.openNewProject` does that).
/// Closing it does not stop a creation: the controller lives as long as the window, and the
/// dialog opens on the progress again while the creation runs or waits for its "Done".
/// {@endtemplate}
class NewProjectDialog extends StatefulWidget {
  /// {@macro new_project_dialog}
  const NewProjectDialog({super.key});

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<NewProjectDialog> {
  late final _creation = WorkspaceConfigInhWidget.of(context).projectCreation;

  /// Closes the dialog and, once it has faded out (so the empty form does not flash), resets the
  /// finished creation.
  void _done() {
    final creation = _creation;
    final animation = ModalRoute.of(context)?.animation;
    Navigator.of(context).pop();
    if (animation == null || animation.isDismissed) {
      creation.reset();
      return;
    }
    void onStatus(AnimationStatus status) {
      if (status != AnimationStatus.dismissed) return;
      animation.removeStatusListener(onStatus);
      if (!creation.isDisposed) creation.reset();
    }

    animation.addStatusListener(onStatus);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
          child: ListenableBuilder(
            listenable: _creation,
            builder: (context, _) => switch (_creation.state) {
              ProjectCreation$IdleState() => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  NewProjectHeader(title: Localization.of(context).newProjectTitle),
                  const Flexible(child: NewProjectForm()),
                ],
              ),
              _ => CreationProgress(controller: _creation, onDone: _done),
            },
          ),
        ),
      ),
    );
  }
}
