import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/add_member_form.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/creation_dialog.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';

/// {@template add_member_dialog}
/// The Add to project dialog: a [CreationDialog] that asks for the new member of a monorepo
/// ([AddMemberForm]) and, once it is being added, shows how it goes.
///
/// It works like the New project dialog and shares its controller: closing it does not stop the
/// run, and it opens on the progress again while a run goes on or waits for its "Close". It has to
/// be shown under a `WorkspaceConfigInhWidget` (`WorkspaceConfigWidgetState.openAddMember` does
/// that).
/// {@endtemplate}
class AddMemberDialog extends StatelessWidget {
  /// {@macro add_member_dialog}
  const AddMemberDialog({required this.project, super.key});

  /// The monorepo the member is added to.
  final Project project;

  @override
  Widget build(BuildContext context) => CreationDialog(
    title: Localization.of(context).addMemberTitle,
    form: AddMemberForm(project: project),
  );
}
