import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_workspace.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_explorer.dart';

/// {@template code_view}
/// The Code view of one project in place of the chat: the explorer, a divider that sets its width,
/// and the editor.
/// {@endtemplate}
class CodeView extends StatelessWidget {
  /// {@macro code_view}
  const CodeView({required this.workspace, required this.onOpenExternally, super.key});

  /// The project's explorer and tabs.
  final CodeWorkspace workspace;

  /// Opens a path in the system's default app.
  final ValueChanged<String> onOpenExternally;

  Future<void> _open(String path) async {
    try {
      await workspace.tabs.open(path);
    } on io.PathNotFoundException {
      // Gone since the explorer listed it; the explorer drops it with the change.
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: workspace.tabs,
    builder: (context, _) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: workspace.tabs.explorerWidth,
          child: CodeExplorer(
            tree: workspace.tree,
            onOpenFile: (path) => _open(path).ignore(),
            onOpenExternally: onOpenExternally,
          ),
        ),
        _Divider(
          onDrag: (delta) => workspace.tabs.setExplorerWidth(workspace.tabs.explorerWidth + delta),
        ),
        Expanded(child: _EditorArea(workspace: workspace)),
      ],
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => MouseRegion(
    key: const ValueKey<String>('code-explorer-divider'),
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      child: SizedBox(
        width: 5,
        child: Center(child: VerticalDivider(width: 1, color: context.colors.border)),
      ),
    ),
  );
}

class _EditorArea extends StatelessWidget {
  const _EditorArea({required this.workspace});

  final CodeWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final active = workspace.tabs.active;
    if (active == null) {
      return Center(
        child: Text(
          Localization.of(context).codeEmptyHint,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colors.muted),
        ),
      );
    }
    // The editor itself comes with the tabs.
    return const SizedBox.shrink();
  }
}
