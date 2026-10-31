/// Splits [text] into command-line arguments on whitespace; text inside double quotes stays in one
/// argument and the quotes are dropped (`-y "@figma/mcp"` → `-y`, `@figma/mcp`).
///
/// An empty pair of quotes is an empty argument; a quote that is never closed takes the rest of the
/// line.
List<String> splitArguments(String text) {
  final arguments = <String>[];
  final current = StringBuffer();
  var inToken = false;
  var quoted = false;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (char == '"') {
      quoted = !quoted;
      inToken = true;
    } else if (!quoted && char.trim().isEmpty) {
      if (inToken) arguments.add(current.toString());
      current.clear();
      inToken = false;
    } else {
      current.write(char);
      inToken = true;
    }
  }
  if (inToken) arguments.add(current.toString());
  return arguments;
}

/// Reads one `key<separator>value` pair per line of [text], ignoring blank lines; both parts are
/// trimmed. The key ends at the first [separator], so the value may contain it.
///
/// Returns `null` when a line has no [separator] or no key.
Map<String, String>? parseKeyValueLines(String text, String separator) {
  final pairs = <String, String>{};
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final at = trimmed.indexOf(separator);
    final key = at < 0 ? '' : trimmed.substring(0, at).trim();
    if (key.isEmpty) return null;
    pairs[key] = trimmed.substring(at + separator.length).trim();
  }
  return pairs;
}
