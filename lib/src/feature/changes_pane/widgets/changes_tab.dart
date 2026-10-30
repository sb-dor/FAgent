import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/feature/changes_pane/models/changed_file.dart';
import 'package:flutter_code_agent/src/feature/changes_pane/widgets/changes_view.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// {@template changes_tab}
/// The Changes tab of the right pane for the open chat: its [files], the file chosen in the
/// workspace, and opening a file with the system.
/// {@endtemplate}
class ChangesTab extends StatelessWidget {
  /// {@macro changes_tab}
  const ChangesTab({required this.files, super.key});

  /// The changed files of the open chat.
  final ValueNotifier<List<ChangedFile>> files;

  @override
  Widget build(BuildContext context) {
    final scope = WorkspaceConfigInhWidget.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[files, scope.dataController]),
      builder: (context, _) => ChangesView(
        files: files.value,
        projectRoot: scope.selectedProject?.path ?? '',
        selectedPath: scope.dataController.selectedChangePath,
        onSelect: scope.dataController.selectChange,
        onOpenFile: (path) => scope.openPath(path).ignore(),
      ),
    );
  }
}
