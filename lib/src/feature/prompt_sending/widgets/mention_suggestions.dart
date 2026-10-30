import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/file_mention/models/file_mention.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/run_mentions.dart';
import 'package:path/path.dart' as p;

/// What a row of the `@` menu stands for.
enum MentionKind {
  /// A project file.
  file,

  /// The widget picked in the running app.
  widget,

  /// The last error of the running app.
  error,

  /// A screenshot of the device (not available yet).
  screenshot,
}

/// One row of the `@` menu.
@immutable
final class MentionRow {
  /// A project file.
  const MentionRow.file(String path)
    : kind = MentionKind.file,
      detail = path,
      insert = '@$path ',
      enabled = true;

  /// A row from the running app; [detail] is its second line, [insert] what it inserts.
  const MentionRow.run(
    this.kind, {
    required this.detail,
    required this.insert,
    this.enabled = true,
  });

  /// What the row stands for.
  final MentionKind kind;

  /// The path of a file; the muted line of a row from the run.
  final String detail;

  /// The text the row inserts, with the trailing space.
  final String insert;

  /// Whether the row can be chosen.
  final bool enabled;

  /// Whether the row comes from the running app and not from the file list.
  bool get fromRun => kind != MentionKind.file;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MentionRow &&
          other.kind == kind &&
          other.detail == detail &&
          other.insert == insert &&
          other.enabled == enabled;

  @override
  int get hashCode => Object.hash(kind, detail, insert, enabled);
}

/// The rows for a typed `@[query]`: what the running app offers first (only when [run] has
/// something and the row matches [query]), then the matching [files].
List<MentionRow> mentionRows(List<String> files, String query, RunMentions? run) {
  final needle = query.toLowerCase();
  bool matches(String text) => needle.isEmpty || text.toLowerCase().contains(needle);
  final fromRun = <MentionRow>[
    if (run != null && !run.isEmpty) ...<MentionRow>[
      if (run.widget case final widget? when matches(widget.text))
        MentionRow.run(MentionKind.widget, detail: widget.detail, insert: '${widget.text} '),
      if (run.error case final error? when matches(error.text))
        MentionRow.run(MentionKind.error, detail: error.detail, insert: '${error.text} '),
      if (matches('screenshot'))
        const MentionRow.run(MentionKind.screenshot, detail: 'M2', insert: '', enabled: false),
    ],
  ];
  return <MentionRow>[
    ...fromRun,
    for (final file in searchFiles(files, query)) MentionRow.file(file),
  ];
}

/// The list under a typed `@`; [highlighted] is the row Enter would insert. Rows from the running
/// app come first, under their own title.
class MentionSuggestions extends StatelessWidget {
  /// Creates the list.
  const MentionSuggestions({
    super.key,
    required this.rows,
    required this.highlighted,
    required this.onSelected,
  });

  final List<MentionRow> rows;
  final int highlighted;
  final ValueChanged<MentionRow> onSelected;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final hasRun = rows.any((row) => row.fromRun);
    Widget title(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: colors.muted, fontWeight: FontWeight.w600),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (index, row) in rows.indexed) ...<Widget>[
            if (hasRun && index == 0) title(localization.fromRun),
            if (hasRun && !row.fromRun && (index == 0 || rows[index - 1].fromRun))
              title(localization.mentionFiles),
            Opacity(
              opacity: row.enabled ? 1 : 0.5,
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  selected: index == highlighted,
                  selectedTileColor: colors.accentSoft,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  leading: Icon(_icon(row.kind), size: 18),
                  title: Text(_title(localization, row)),
                  subtitle: _subtitle(localization, row),
                  onTap: row.enabled ? () => onSelected(row) : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _icon(MentionKind kind) => switch (kind) {
    MentionKind.file => Icons.description_outlined,
    MentionKind.widget => Icons.ads_click,
    MentionKind.error => Icons.warning_amber_rounded,
    MentionKind.screenshot => Icons.photo_camera_outlined,
  };

  static String _title(GeneratedLocalization localization, MentionRow row) => switch (row.kind) {
    MentionKind.file => p.basename(row.detail),
    MentionKind.widget => localization.selectedWidget,
    MentionKind.error => localization.lastError,
    MentionKind.screenshot => localization.screenshot,
  };

  static Widget? _subtitle(GeneratedLocalization localization, MentionRow row) {
    final text = switch (row.kind) {
      MentionKind.file => p.dirname(row.detail) == '.' ? '' : p.dirname(row.detail),
      MentionKind.screenshot => localization.comingInMilestone(row.detail),
      _ => row.detail,
    };
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}
