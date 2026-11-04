import 'package:meta/meta.dart';

/// {@template lsp_position}
/// A position in a document as LSP counts it: 0-based line, 0-based UTF-16 column (what Dart
/// strings index).
/// {@endtemplate}
@immutable
final class LspPosition {
  /// {@macro lsp_position}
  const LspPosition({required this.line, required this.character});

  /// Parses `{line, character}`.
  factory LspPosition.fromJson(Object? json) {
    final map = json is Map ? json : const <String, Object?>{};
    return LspPosition(
      line: (map['line'] as num?)?.toInt() ?? 0,
      character: (map['character'] as num?)?.toInt() ?? 0,
    );
  }

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

  /// Parses `{start, end}`.
  factory LspRange.fromJson(Object? json) {
    final map = json is Map ? json : const <String, Object?>{};
    return LspRange(
      start: LspPosition.fromJson(map['start']),
      end: LspPosition.fromJson(map['end']),
    );
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

  /// Parses `{range, newText}`.
  factory LspTextEdit.fromJson(Object? json) {
    final map = json is Map ? json : const <String, Object?>{};
    return LspTextEdit(range: LspRange.fromJson(map['range']), newText: '${map['newText'] ?? ''}');
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
