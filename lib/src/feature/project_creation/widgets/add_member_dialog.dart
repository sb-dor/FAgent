import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/project_creation/controller/project_creation_controller.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/add_member_form.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/creation_progress.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/new_project_header.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// {@template add_member_dialog}
/// The Add to project dialog: a 560 px dialog that asks for the new member of a monorepo
/// ([AddMemberForm]) and, once it is being added, shows how it goes ([CreationProgress]).
///
/// It works like the New project dialog and shares its [ProjectCreationController]: closing it
/// does not stop the run, and it opens on the progress again while a run goes on or waits for its
/// "Close". It has to be shown under a [WorkspaceConfigInhWidget]
/// (`WorkspaceConfigWidgetState.openAddMember` does that).
/// {@endtemplate}
class AddMemberDialog extends StatefulWidget {
  /// {@macro add_member_dialog}
  const AddMemberDialog({required this.project, super.key});

  /// The monorepo the member is added to.
  final Project project;

  @override
  State<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<AddMemberDialog> {
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
                  NewProjectHeader(title: Localization.of(context).addMemberTitle),
                  Flexible(child: AddMemberForm(project: widget.project)),
                ],
              ),
              _ => CreationProgress(
                controller: _creation,
                onClose: _close,
                // An added member has no project to open: the button never shows.
                onOpenProject: (_) => _close(),
              ),
            },
          ),
        ),
      ),
    );
  }
}
