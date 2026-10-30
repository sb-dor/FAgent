import 'package:path/path.dart' as p;

// `@` mentions in the prompt text.

final RegExp _query = RegExp(r'(?:^|\s)@([^\s@]*)$');

/// The mention being typed right before [cursor]: its start (the `@`) and
/// the query after it. `null` when the cursor is not in a mention.
({int start, String query})? mentionQueryAt(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  final match = _query.firstMatch(text.substring(0, cursor));
  if (match == null) return null;
  final query = match.group(1)!;
  return (start: cursor - query.length - 1, query: query);
}

/// Up to [limit] of [files] matching [query]: a file name prefix first, then
/// a file name or path containing it, then the letters in order.
List<String> searchFiles(List<String> files, String query, {int limit = 8}) {
  final needle = query.toLowerCase();
  if (needle.isEmpty) return files.take(limit).toList();
  final ranked = <(int, String)>[];
  for (final file in files) {
    final path = file.toLowerCase();
    final name = p.basename(path);
    final rank = name.startsWith(needle)
        ? 0
        : name.contains(needle)
        ? 1
        : path.contains(needle)
        ? 2
        : _inOrder(path, needle)
        ? 3
        : null;
    if (rank != null) ranked.add((rank, file));
  }
  ranked.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    return byRank != 0 ? byRank : a.$2.length.compareTo(b.$2.length);
  });
  return <String>[for (final (_, file) in ranked.take(limit)) file];
}

bool _inOrder(String path, String needle) {
  var i = 0;
  for (final unit in path.codeUnits) {
    if (i < needle.length && unit == needle.codeUnitAt(i)) i++;
  }
  return i == needle.length;
}

/// A mention found in a text: `text.substring(start, end)` is `@` plus [path].
typedef MentionRange = ({int start, int end, String path});

/// Mentions of [text] whose path is among [files], in order. A mention is `@`
/// at the start or after whitespace followed by the longest known path, so
/// paths with spaces or `@` (`Icon@2x.png`) work and punctuation after a path
/// (`@main.dart,`) is not part of it.
List<MentionRange> mentionRanges(String text, Iterable<String> files) {
  final found = <MentionRange>[];
  for (var at = text.indexOf('@'); at != -1; at = text.indexOf('@', at + 1)) {
    if (at > 0 && !_isSpace(text.codeUnitAt(at - 1))) continue;
    String? longest;
    for (final file in files) {
      if (file.length > (longest?.length ?? 0) &&
          text.startsWith(file, at + 1) &&
          _endsMention(text, at + 1 + file.length)) {
        longest = file;
      }
    }
    if (longest != null) found.add((start: at, end: at + 1 + longest.length, path: longest));
  }
  return found;
}

/// Mentioned paths of [text] that are among [files], in order, once each
/// (see [mentionRanges]).
List<String> mentionedFiles(String text, Set<String> files) =>
    <String>{for (final range in mentionRanges(text, files)) range.path}.toList();

bool _isSpace(int unit) => unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

bool _endsMention(String text, int end) =>
    end == text.length || _isSpace(text.codeUnitAt(end)) || '.,;:!?)]}\'"'.contains(text[end]);

/// ACP `resource_link` blocks for [paths] relative to [root].
List<Map<String, Object?>> resourceLinks(String root, List<String> paths) => <Map<String, Object?>>[
  for (final path in paths)
    <String, Object?>{
      'type': 'resource_link',
      'uri': Uri.file(p.join(root, path)).toString(),
      'name': p.basename(path),
    },
];
