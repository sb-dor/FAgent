import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/turn_files/models/file_change_kind.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// {@template changed_file}
/// A file the chat changed: what git saw ([status]) and what the agent edited ([diffs]).
/// {@endtemplate}
@immutable
final class ChangedFile {
  /// {@macro changed_file}
  const ChangedFile({required this.path, required this.status, required this.diffs});

  /// Status of a file only the agent's diffs mention (no git status for it).
  static const String edited = 'edited';

  /// Absolute, normalized path.
  final String path;

  /// A [FileChangeKind] name other than `clean` (reverted files are not listed), or [edited].
  final String status;

  /// Every diff of the agent for this file, in feed order. Empty when a command changed it.
  final List<ToolDiffContent> diffs;
}

/// The files changed in a chat's [items], the most recently changed first.
///
/// Files from `TurnFilesItem`s (relative to the git root of the turn, or to [projectRoot] in old
/// journals) and from tool diffs are one file when their normalized absolute paths are equal. The
/// last git status wins, a file whose last status is `clean` was reverted and is left out, and
/// without a git status the file is [ChangedFile.edited].
List<ChangedFile> collectChanges(List<ChatItem> items, {required String projectRoot}) {
  // Insertion order tracks the last change: a file touched again moves to the end.
  final entries = <String, _Entry>{};
  _Entry touch(String path) {
    final entry = entries.remove(path) ?? _Entry();
    return entries[path] = entry;
  }

  for (final item in items) {
    switch (item) {
      case TurnFilesItem(:final files, :final root):
        for (final file in files) {
          touch(p.normalize(p.join(root ?? projectRoot, file.path))).kind = fileChangeKind(
            file.status,
          );
        }
      case ToolCallItem(:final diffs):
        for (final diff in diffs) {
          final entry = touch(p.normalize(p.join(projectRoot, diff.path)));
          entry.diffs.add(diff);
          // A change after the revert is not covered by the earlier status.
          if (entry.kind == FileChangeKind.clean) entry.kind = null;
        }
      default:
        break;
    }
  }

  return <ChangedFile>[
    for (final MapEntry(:key, :value) in entries.entries.toList().reversed)
      if (value.kind != FileChangeKind.clean)
        ChangedFile(
          path: key,
          status: value.kind?.name ?? ChangedFile.edited,
          diffs: List<ToolDiffContent>.unmodifiable(value.diffs),
        ),
  ];
}

class _Entry {
  FileChangeKind? kind;
  final List<ToolDiffContent> diffs = <ToolDiffContent>[];
}
