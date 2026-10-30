import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/changes_pane/models/changed_file.dart';
import 'package:flutter_code_agent/src/feature/chat/models/tool_row_label.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/tool_path_text.dart';
import 'package:flutter_code_agent/src/feature/turn_files/models/file_change_kind.dart';
import 'package:flutter_code_agent/src/feature/turn_files/widgets/file_change_label.dart';

/// {@template changes_file_list}
/// The files of the Changes tab: name (mono) with its folder (muted), what happened to the file
/// and the `+N −M` of its diffs. The [selected] row is highlighted.
/// {@endtemplate}
class ChangesFileList extends StatelessWidget {
  /// {@macro changes_file_list}
  const ChangesFileList({
    required this.files,
    required this.counters,
    required this.selected,
    required this.projectRoot,
    required this.onSelect,
    super.key,
  });

  /// Files in display order.
  final List<ChangedFile> files;

  /// `+N −M` of each of [files]; `null` for a file without diffs.
  final List<({int added, int removed})?> counters;

  /// Absolute path of the highlighted file.
  final String selected;

  /// Paths inside it are shown relative to it.
  final String projectRoot;

  /// Called with the path of the tapped file.
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => ListView.builder(
    shrinkWrap: true,
    padding: const EdgeInsets.all(8),
    itemCount: files.length,
    itemBuilder: (context, index) => _FileRow(
      file: files[index],
      counter: counters[index],
      selected: files[index].path == selected,
      projectRoot: projectRoot,
      onTap: () => onSelect(files[index].path),
    ),
  );
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.counter,
    required this.selected,
    required this.projectRoot,
    required this.onTap,
  });

  final ChangedFile file;
  final ({int added, int removed})? counter;
  final bool selected;
  final String projectRoot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppRadius.small);
    final counter = this.counter;
    final kind = file.status == ChangedFile.edited
        ? FileChangeKind.modified
        : FileChangeKind.values.byName(file.status);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? colors.bg : Colors.transparent,
        borderRadius: radius,
        border: Border.all(color: selected ? colors.border : Colors.transparent),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ToolPathText(
                    label: toolRowLabel(title: '', path: file.path, projectRoot: projectRoot),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  fileChangeLabel(Localization.of(context), kind),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.muted),
                ),
                if (counter != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: '+${counter.added}',
                          style: TextStyle(color: colors.ok),
                        ),
                        const TextSpan(text: ' '),
                        TextSpan(
                          text: '−${counter.removed}',
                          style: TextStyle(color: colors.danger),
                        ),
                      ],
                    ),
                    style: AppText.mono(context),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
