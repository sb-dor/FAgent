import 'package:path/path.dart' as p;

// `@` mentions in the prompt text.

final RegExp _query = RegExp(r'(?:^|\s)@([^\s@]*)$');
final RegExp _mention = RegExp(r'(?:^|\s)@([^\s@]+)');

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

final RegExp _trailingPunctuation = RegExp(r'''[.,;:!?)\]}'"]+$''');

/// Mentioned paths of [text] that are among [files], in order, once each.
/// Punctuation right after a path (`@main.dart,`) is not part of it.
List<String> mentionedFiles(String text, Set<String> files) => <String>{
  for (final match in _mention.allMatches(text))
    if (_known(match.group(1)!, files) case final String path) path,
}.toList();

String? _known(String mention, Set<String> files) {
  if (files.contains(mention)) return mention;
  final trimmed = mention.replaceFirst(_trailingPunctuation, '');
  return files.contains(trimmed) ? trimmed : null;
}

/// ACP `resource_link` blocks for [paths] relative to [root].
List<Map<String, Object?>> resourceLinks(String root, List<String> paths) => <Map<String, Object?>>[
  for (final path in paths)
    <String, Object?>{
      'type': 'resource_link',
      'uri': Uri.file(p.join(root, path)).toString(),
      'name': p.basename(path),
    },
];
