import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/utils/line_diff.dart';
import 'package:flutter_code_agent/src/common/widget/diff_view.dart';
import 'package:flutter_code_agent/src/common/widget/empty_state.dart';
import 'package:flutter_code_agent/src/feature/changes_pane/models/changed_file.dart';
import 'package:flutter_code_agent/src/feature/changes_pane/widgets/changes_file_list.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/diff_lines_cache.dart';
import 'package:flutter_code_agent/src/feature/turn_files/models/file_change_kind.dart';
import 'package:path/path.dart' as p;

/// {@template changes_view}
/// The Changes tab: the changed files on top (at most 40 % of the height, scrolling) and the
/// diffs of the selected file below. Without files it is an empty state.
///
/// The selected file is [selectedPath] when that file is listed, else the first one.
/// {@endtemplate}
class ChangesView extends StatefulWidget {
  /// {@macro changes_view}
  const ChangesView({
    required this.files,
    required this.projectRoot,
    required this.selectedPath,
    required this.onSelect,
    required this.onOpenFile,
    super.key,
  });

  /// Files to list.
  final List<ChangedFile> files;

  /// The project folder; paths inside it are shown relative to it.
  final String projectRoot;

  /// Path the user chose, if any.
  final String? selectedPath;

  /// Called with the path of a file the user picked.
  final ValueChanged<String?> onSelect;

  /// Called with the absolute path of a file the user wants to open.
  final ValueChanged<String> onOpenFile;

  @override
  State<ChangesView> createState() => _ChangesViewState();
}

class _ChangesViewState extends State<ChangesView> {
  final DiffLinesCache _diffLines = DiffLinesCache();

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final files = widget.files;
    if (files.isEmpty) {
      return EmptyState(
        icon: Icons.difference_outlined,
        title: localization.changesEmpty,
        message: localization.changesEmptyHint,
      );
    }
    final wanted = widget.selectedPath == null ? null : p.normalize(widget.selectedPath!);
    final selected = files.firstWhere((file) => file.path == wanted, orElse: () => files.first);

    // One cache for every diff, so a streamed chunk does not recompute the unchanged ones.
    final all = <ToolDiffContent>[for (final file in files) ...file.diffs];
    final resolved = _diffLines.resolve(all);
    final lines = <String, List<List<DiffLine>>>{};
    var offset = 0;
    for (final file in files) {
      lines[file.path] = resolved.sublist(offset, offset += file.diffs.length);
    }
    final counters = <({int added, int removed})?>[
      for (final file in files) _sum(lines[file.path]!),
    ];

    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.4),
            child: ChangesFileList(
              files: files,
              counters: counters,
              selected: selected.path,
              projectRoot: widget.projectRoot,
              onSelect: widget.onSelect,
            ),
          ),
          Divider(height: 1, color: context.colors.border),
          Expanded(
            child: selected.diffs.isEmpty
                ? _NoDiff(
                    path: selected.path,
                    canOpen: selected.status != FileChangeKind.deleted.name,
                    onOpenFile: widget.onOpenFile,
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: <Widget>[
                      for (var i = 0; i < selected.diffs.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: DiffView(
                            path: selected.diffs[i].path,
                            oldText: selected.diffs[i].oldText,
                            newText: selected.diffs[i].newText,
                            lines: lines[selected.path]![i],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// `+N −M` over [diffs]; `null` without any.
({int added, int removed})? _sum(List<List<DiffLine>> diffs) {
  if (diffs.isEmpty) return null;
  var added = 0;
  var removed = 0;
  for (final lines in diffs) {
    final stats = LineDiff.stats(lines);
    added += stats.added;
    removed += stats.removed;
  }
  return (added: added, removed: removed);
}

/// A file a command changed: there is no diff, only the file itself to open.
class _NoDiff extends StatelessWidget {
  const _NoDiff({required this.path, required this.canOpen, required this.onOpenFile});

  final String path;

  /// A deleted file is not there to open.
  final bool canOpen;
  final ValueChanged<String> onOpenFile;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    return EmptyState(
      icon: Icons.terminal,
      title: localization.changedByCommand,
      actionLabel: canOpen ? localization.openFile : null,
      onAction: canOpen ? () => onOpenFile(path) : null,
    );
  }
}
