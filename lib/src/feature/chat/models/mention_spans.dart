import 'package:flutter/painting.dart';
import 'package:flutter_code_agent/src/feature/file_mention/models/file_mention.dart';

/// Splits [text] into plain spans and `@path` pills.
///
/// [resourceUris] are the attached files of the message (`Uri.file(...)`
/// strings). A mention is found like the composer finds it
/// (`mentionRanges`), where the known paths are the decoded file paths and
/// their tails after a `/` — the composer wrote `@<path relative to the
/// project>`, the URI holds the absolute path.
List<InlineSpan> mentionSpans(String text, List<String> resourceUris, {required TextStyle pill}) {
  final spans = <InlineSpan>[];
  var plainStart = 0;
  for (final range in mentionRanges(text, _knownPaths(resourceUris))) {
    if (range.start > plainStart) {
      spans.add(TextSpan(text: text.substring(plainStart, range.start)));
    }
    spans.add(TextSpan(text: text.substring(range.start, range.end), style: pill));
    plainStart = range.end;
  }
  if (plainStart < text.length || spans.isEmpty) {
    spans.add(TextSpan(text: text.substring(plainStart)));
  }
  return spans;
}

/// Decoded paths of [uris] and every tail of them that starts after a `/`.
Set<String> _knownPaths(List<String> uris) {
  final paths = <String>{};
  for (final uri in uris) {
    final path = _decodedPath(uri);
    if (path == null) continue;
    paths.add(path);
    for (var slash = path.indexOf('/'); slash != -1; slash = path.indexOf('/', slash + 1)) {
      if (slash + 1 < path.length) paths.add(path.substring(slash + 1));
    }
  }
  return paths;
}

String? _decodedPath(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null) return null;
  try {
    return parsed.isScheme('file') ? parsed.toFilePath() : Uri.decodeComponent(parsed.path);
  } on Object {
    return null;
  }
}
