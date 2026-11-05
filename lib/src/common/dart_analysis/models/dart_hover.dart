import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_range.dart';
import 'package:meta/meta.dart';

/// {@template dart_hover}
/// What the analysis server says about the name at a position: its declaration and dartdoc as
/// markdown, and the name's range.
/// {@endtemplate}
@immutable
final class DartHover {
  /// {@macro dart_hover}
  const DartHover({required this.markdown, this.range});

  /// Parses a `Hover`; `null` when it has no text.
  ///
  /// `contents` may be `MarkupContent` (`{kind, value}`), a plain string, or a list of them.
  static DartHover? fromJson(Object? json) {
    if (json is! Map) return null;
    final markdown = _text(json['contents']).trim();
    if (markdown.isEmpty) return null;
    final range = json['range'];
    return DartHover(markdown: markdown, range: range is Map ? LspRange.fromJson(range) : null);
  }

  static String _text(Object? contents) => switch (contents) {
    final String text => text,
    {'value': final Object? value} => '${value ?? ''}',
    final List<Object?> parts => parts.map(_text).where((part) => part.isNotEmpty).join('\n\n'),
    _ => '',
  };

  /// The declaration (a fenced `dart` block) and the dartdoc.
  final String markdown;

  /// The name the hover is about.
  final LspRange? range;

  @override
  bool operator ==(Object other) =>
      other is DartHover && other.markdown == markdown && other.range == range;

  @override
  int get hashCode => Object.hash(markdown, range);

  @override
  String toString() => 'DartHover(${markdown.length} chars, $range)';
}
