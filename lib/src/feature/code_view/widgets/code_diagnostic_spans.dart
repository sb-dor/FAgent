import 'package:flutter/painting.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_diagnostic.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';

/// The color of a [severity] underline.
Color diagnosticColor(AppColors colors, DartSeverity severity) => switch (severity) {
  DartSeverity.error => colors.danger,
  DartSeverity.warning => colors.warn,
  DartSeverity.info || DartSeverity.hint => colors.muted,
};

/// [textSpan] (the highlighted text of [line]) with a wavy underline under the part of every
/// diagnostic on that line, in its severity's color (the hover card shows their messages). A line
/// without diagnostics comes back as it is.
TextSpan diagnosticSpans({
  required TextSpan textSpan,
  required int line,
  required List<DartDiagnostic> diagnostics,
  required AppColors colors,
}) {
  // Each diagnostic's columns on this line; the worst severity first, so it wins where they meet.
  final parts = <(int, int, DartDiagnostic)>[
    for (final diagnostic in diagnostics)
      if (diagnostic.range.start.line <= line && diagnostic.range.end.line >= line)
        (
          diagnostic.range.start.line == line ? diagnostic.range.start.character : 0,
          diagnostic.range.end.line == line ? diagnostic.range.end.character : 1 << 30,
          diagnostic,
        ),
  ]..sort((a, b) => a.$3.severity.index.compareTo(b.$3.severity.index));
  if (parts.isEmpty) return textSpan;

  // The leaves of the highlighted span, with their styles merged down.
  final leaves = <(String, TextStyle?)>[];
  void flatten(InlineSpan span, TextStyle? inherited) {
    if (span is! TextSpan) return;
    final style = inherited == null ? span.style : inherited.merge(span.style);
    if (span.text case final text? when text.isNotEmpty) leaves.add((text, style));
    for (final child in span.children ?? const <InlineSpan>[]) {
      flatten(child, style);
    }
  }

  flatten(textSpan, null);
  final length = leaves.fold(0, (sum, leaf) => sum + leaf.$1.length);

  // Cut at every leaf and part boundary, then give each piece its part.
  final cuts = <int>{0, length};
  var offset = 0;
  for (final (text, _) in leaves) {
    offset += text.length;
    cuts.add(offset);
  }
  for (final (start, end, _) in parts) {
    cuts
      ..add(start.clamp(0, length))
      ..add(end.clamp(0, length));
  }
  final sorted = cuts.toList()..sort();

  DartDiagnostic? partAt(int position) {
    for (final (start, end, diagnostic) in parts) {
      if (start <= position && position < end) return diagnostic;
    }
    return null;
  }

  (String, TextStyle?) leafAt(int position) {
    var start = 0;
    for (final leaf in leaves) {
      if (position < start + leaf.$1.length) return (leaf.$1.substring(position - start), leaf.$2);
      start += leaf.$1.length;
    }
    return ('', null);
  }

  final children = <InlineSpan>[];
  for (var i = 0; i + 1 < sorted.length; i++) {
    final from = sorted[i];
    final to = sorted[i + 1];
    if (from == to) continue;
    final (rest, style) = leafAt(from);
    final text = rest.substring(0, to - from);
    final diagnostic = partAt(from);
    if (diagnostic == null) {
      children.add(TextSpan(text: text, style: style));
      continue;
    }
    children.add(
      TextSpan(
        text: text,
        style: (style ?? const TextStyle()).copyWith(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.wavy,
          decorationColor: diagnosticColor(colors, diagnostic.severity),
        ),
      ),
    );
  }
  return TextSpan(style: textSpan.style, children: children);
}
