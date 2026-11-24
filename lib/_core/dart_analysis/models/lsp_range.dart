import 'package:meta/meta.dart';

/// {@template lsp_position}
/// A position in a document as LSP counts it: 0-based line, 0-based UTF-16 column (what Dart
/// strings index).
/// {@endtemplate}
@immutable
final class LspPosition {
  /// {@macro lsp_position}
  const LspPosition({required this.line, required this.character});

  /// Parses `{line, character}`; `null` when either is missing or not a number.
  static LspPosition? fromJson(Object? json) => switch (json) {
    {'line': final num line, 'character': final num character} => LspPosition(
      line: line.toInt(),
      character: character.toInt(),
    ),
    _ => null,
  };

  /// 0-based line.
  final int line;

  /// 0-based UTF-16 column.
  final int character;

  /// `{line, character}`.
  Map<String, Object?> toJson() => <String, Object?>{'line': line, 'character': character};

  @override
  bool operator ==(Object other) =>
      other is LspPosition && other.line == line && other.character == character;

  @override
  int get hashCode => Object.hash(line, character);

  @override
  String toString() => '$line:$character';
}

/// {@template lsp_range}
/// A range of a document, [end] excluded.
/// {@endtemplate}
@immutable
final class LspRange {
  /// {@macro lsp_range}
  const LspRange({required this.start, required this.end});

  /// Parses `{start, end}`; `null` when either position is malformed.
  static LspRange? fromJson(Object? json) {
    if (json is! Map) return null;
    final start = LspPosition.fromJson(json['start']);
    final end = LspPosition.fromJson(json['end']);
    return start == null || end == null ? null : LspRange(start: start, end: end);
  }

  /// First position.
  final LspPosition start;

  /// The position after the last one.
  final LspPosition end;

  @override
  bool operator ==(Object other) => other is LspRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start-$end';
}

/// {@template lsp_text_edit}
/// Replace [range] with [newText].
/// {@endtemplate}
@immutable
final class LspTextEdit {
  /// {@macro lsp_text_edit}
  const LspTextEdit({required this.range, required this.newText});

  /// Parses `{range, newText}`; `null` when the range is malformed or `newText` is not a string.
  static LspTextEdit? fromJson(Object? json) {
    if (json case {'newText': final String newText, 'range': final Object? rangeJson}) {
      if (LspRange.fromJson(rangeJson) case final range?) {
        return LspTextEdit(range: range, newText: newText);
      }
    }
    return null;
  }

  /// What is replaced.
  final LspRange range;

  /// What it becomes.
  final String newText;

  @override
  bool operator ==(Object other) =>
      other is LspTextEdit && other.range == range && other.newText == newText;

  @override
  int get hashCode => Object.hash(range, newText);

  @override
  String toString() => 'LspTextEdit($range, ${newText.length} chars)';
}
