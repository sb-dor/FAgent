import 'package:flutter_code_agent/_core/design/app_colors.dart';
import 'package:flutter_code_agent/_core/design/app_theme.dart';
import 'package:flutter_code_agent/project_creation/controller/project_creation_controller.dart';
import 'package:flutter_code_agent/project_creation/widgets/creation_progress.dart';
import 'package:flutter_code_agent/project_creation/widgets/new_project_header.dart';
import 'package:flutter_code_agent/workspace/widgets/workspace_config_widget.dart';
import 'package:material_ui/material_ui.dart';

/// {@template creation_dialog}
/// The shell of the New project and Add to project dialogs: a 560 px dialog that shows [title] and
/// [form] while the window's [ProjectCreationController] is idle and its [CreationProgress]
/// otherwise.
///
/// Both dialogs share one controller, so whichever run the controller holds is shown, whoever
/// started it: "Open project" of a finished run opens the created project in the workspace (with
/// a chat if the request asked for one), and "Close" resets the run once the dialog has faded out.
/// Closing the dialog does not stop a run. It has to be shown under a [WorkspaceConfigInhWidget].
/// {@endtemplate}
class CreationDialog extends StatefulWidget {
  /// {@macro creation_dialog}
  const CreationDialog({required this.title, required this.form, super.key});

  /// The header while the form is shown.
  final String title;

  /// What the dialog asks while nothing is being created.
  final Widget form;

  @override
  State<CreationDialog> createState() => _CreationDialogState();
}

class _CreationDialogState extends State<CreationDialog> {
  late final _creation = WorkspaceConfigInhWidget.of(context).projectCreation;

  /// Closes the dialog and, once it has faded out (so the empty form does not flash), resets the
  /// finished run.
  void _close() {
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

  /// Closes the dialog as [_close] does and opens the created project [projectId].
  void _openProject(int projectId) {
    final workspace = WorkspaceConfigInhWidget.of(context);
    final openChat = switch (_creation.state) {
      ProjectCreation$CompletedState(:final request) ||
      ProjectCreation$FailedState(:final request) => (request?.openChat ?? false),
      _ => false,
    };
    _close();
    workspace.openCreatedProject(projectId, openChat: openChat);
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
                  NewProjectHeader(title: widget.title),
                  Flexible(child: widget.form),
                ],
              ),
              _ => CreationProgress(
                controller: _creation,
                onClose: _close,
                onOpenProject: _openProject,
              ),
            },
          ),
        ),
      ),
    );
  }
}
