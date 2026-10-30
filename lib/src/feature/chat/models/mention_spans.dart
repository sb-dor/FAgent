import 'package:flutter/painting.dart';

/// Splits [text] into plain spans and `@path` pills.
///
/// A mention is highlighted with [pill] when one of [resourceUris] ends with
/// `/<path>` (the composer writes `@<path relative to the project>`).
List<InlineSpan> mentionSpans(String text, List<String> resourceUris, {required TextStyle pill}) {
  final spans = <InlineSpan>[];
  var plainStart = 0;
  for (final match in _mention.allMatches(text)) {
    final path = match.group(1)!;
    if (!resourceUris.any((uri) => uri.endsWith('/$path'))) continue;
    if (match.start > plainStart) {
      spans.add(TextSpan(text: text.substring(plainStart, match.start)));
    }
    spans.add(TextSpan(text: match.group(0), style: pill));
    plainStart = match.end;
  }
  if (plainStart < text.length || spans.isEmpty) {
    spans.add(TextSpan(text: text.substring(plainStart)));
  }
  return spans;
}

final RegExp _mention = RegExp(r'@([^\s@]+)');
