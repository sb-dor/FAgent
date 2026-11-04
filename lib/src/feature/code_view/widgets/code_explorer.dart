import 'package:control/control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/file_tree_controller.dart';

/// {@template code_explorer}
/// The project's folders and files: one flat list of the visible rows, so a folder with thousands
/// of entries scrolls smoothly. A click opens a file or opens and closes a folder; the context menu
/// opens the entry in the system's default app.
/// {@endtemplate}
class CodeExplorer extends StatelessWidget {
  /// {@macro code_explorer}
  const CodeExplorer({
    required this.tree,
    required this.onOpenFile,
    required this.onOpenExternally,
    super.key,
  });

  /// The explorer's state.
  final FileTreeController tree;

  /// Called with the absolute path of a clicked file.
  final ValueChanged<String> onOpenFile;

  /// Called with the absolute path chosen in the context menu.
  final ValueChanged<String> onOpenExternally;

  /// Indent per folder level.
  static const double indent = 12;

  /// Height of a row.
  static const double rowHeight = 24;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.surface,
    child: StateConsumer<FileTreeController, FileTreeState>(
      controller: tree,
      builder: (context, state, _) => switch (state) {
        FileTree$LoadingState() => const SizedBox.shrink(),
        FileTree$MissingState() => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              Localization.of(context).codeProjectFolderMissing,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.muted),
            ),
          ),
        ),
        FileTree$LoadedState(:final rows) => ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemExtent: rowHeight,
          itemCount: rows.length,
          itemBuilder: (context, index) => _Row(
            row: rows[index],
            onTap: () {
              final node = rows[index].node;
              node.isDirectory ? tree.toggle(node.path) : onOpenFile(node.path);
            },
            onOpenExternally: () => onOpenExternally(rows[index].node.path),
          ),
        ),
      },
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.onTap, required this.onOpenExternally});

  final FileTreeRow row;
  final VoidCallback onTap;
  final VoidCallback onOpenExternally;

  Future<void> _menu(BuildContext context, Offset position) async {
    final choice = await showAppMenu<bool>(
      context: context,
      anchor: Rect.fromLTWH(position.dx, position.dy, 0, 0),
      width: 260,
      sections: <AppMenuSection<bool>>[
        AppMenuSection<bool>(
          items: <AppMenuItem<bool>>[
            AppMenuItem<bool>(
              value: true,
              title: Localization.of(context).codeOpenExternally,
              icon: Icons.open_in_new,
            ),
          ],
        ),
      ],
    );
    if (choice ?? false) onOpenExternally();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final node = row.node;
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: node.ignored ? colors.muted : colors.text);
    return InkWell(
      onTap: onTap,
      onSecondaryTapUp: (details) => _menu(context, details.globalPosition),
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: Padding(
        padding: EdgeInsets.only(left: 6 + row.depth * CodeExplorer.indent, right: 6),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 16,
              child: node.isDirectory
                  ? Icon(
                      row.expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 14,
                      color: colors.muted,
                    )
                  : null,
            ),
            Icon(
              node.isDirectory
                  ? (row.expanded ? Icons.folder_open_outlined : Icons.folder_outlined)
                  : Icons.description_outlined,
              size: 14,
              color: colors.muted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(node.name, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
