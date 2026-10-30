// ignore_for_file: avoid_classes_with_only_static_members

import 'package:meta/meta.dart';

/// Kind of a diff line.
enum DiffLineKind {
  /// Present on both sides.
  same,

  /// Only in the old text.
  removed,

  /// Only in the new text.
  added,
}

/// One line of a unified diff.
@immutable
final class DiffLine {
  /// Creates a diff line.
  const DiffLine(this.kind, this.text);

  /// Whether the line was kept, removed or added.
  final DiffLineKind kind;

  /// Line text without the newline.
  final String text;

  @override
  bool operator ==(Object other) => other is DiffLine && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() =>
      '${switch (kind) {
        DiffLineKind.same => ' ',
        DiffLineKind.removed => '-',
        DiffLineKind.added => '+',
      }}$text';
}

/// Line diff for the edit cards (LCS; agent edits are small).
abstract final class LineDiff {
  /// Above this many cells the LCS table is skipped and the change is shown
  /// as all old lines removed, all new lines added.
  static const int maxCells = 4000000;

  /// Diff of [oldText] (`null` for a new file) and [newText].
  static List<DiffLine> compute(String? oldText, String newText) {
    final before = oldText == null || oldText.isEmpty ? const <String>[] : oldText.split('\n');
    final after = newText.isEmpty ? const <String>[] : newText.split('\n');
    if (before.length * after.length > maxCells) {
      return <DiffLine>[
        for (final line in before) DiffLine(DiffLineKind.removed, line),
        for (final line in after) DiffLine(DiffLineKind.added, line),
      ];
    }
    // lcs[i][j]: length of the LCS of before[i..] and after[j..].
    final lcs = List<List<int>>.generate(
      before.length + 1,
      (_) => List<int>.filled(after.length + 1, 0),
    );
    for (var i = before.length - 1; i >= 0; i--) {
      for (var j = after.length - 1; j >= 0; j--) {
        lcs[i][j] = before[i] == after[j]
            ? lcs[i + 1][j + 1] + 1
            : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
      }
    }
    final lines = <DiffLine>[];
    var i = 0;
    var j = 0;
    while (i < before.length && j < after.length) {
      if (before[i] == after[j]) {
        lines.add(DiffLine(DiffLineKind.same, before[i]));
        i++;
        j++;
      } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
        lines.add(DiffLine(DiffLineKind.removed, before[i++]));
      } else {
        lines.add(DiffLine(DiffLineKind.added, after[j++]));
      }
    }
    while (i < before.length) {
      lines.add(DiffLine(DiffLineKind.removed, before[i++]));
    }
    while (j < after.length) {
      lines.add(DiffLine(DiffLineKind.added, after[j++]));
    }
    return lines;
  }

  /// Number of added and removed lines.
  static ({int added, int removed}) stats(List<DiffLine> lines) => (
    added: lines.where((l) => l.kind == DiffLineKind.added).length,
    removed: lines.where((l) => l.kind == DiffLineKind.removed).length,
  );
}
