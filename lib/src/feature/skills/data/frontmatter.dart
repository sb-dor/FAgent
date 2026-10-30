import 'dart:convert';

import 'package:yaml/yaml.dart';

/// The YAML header of a `SKILL.md` or a rule file is not valid.
final class FrontmatterException implements Exception {
  /// Creates the exception.
  const FrontmatterException(this.message);

  /// What is wrong with the header.
  final String message;

  @override
  String toString() => 'FrontmatterException: $message';
}

const String _fence = '---';

/// Splits a Markdown [text] into its YAML frontmatter [fields] and the [body] after it.
///
/// Returns `null` when the text has no frontmatter: it does not start with `---` on its own line
/// or the closing `---` is missing. Throws [FrontmatterException] when the header is broken YAML
/// or not a map. Values that are not strings are converted with `toString()` and trimmed; a nested
/// `metadata.version` becomes `version` when there is no top-level one.
({Map<String, String> fields, String body})? parseFrontmatter(String text) {
  final lines = text.split('\n');
  if (lines.first.trimRight() != _fence) return null;

  var closing = -1;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trimRight() == _fence) {
      closing = i;
      break;
    }
  }
  if (closing == -1) return null;

  final Object? yaml;
  try {
    yaml = loadYaml(lines.sublist(1, closing).join('\n'));
  } on YamlException catch (error) {
    throw FrontmatterException(error.message);
  }
  if (yaml != null && yaml is! Map<Object?, Object?>) {
    throw const FrontmatterException('The frontmatter is not a map');
  }

  final fields = <String, String>{
    if (yaml case final Map<Object?, Object?> map)
      for (final entry in map.entries) '${entry.key}': _asString(entry.value),
  };
  if (!fields.containsKey('version') && yaml is Map<Object?, Object?>) {
    final metadata = yaml['metadata'];
    final version = metadata is Map<Object?, Object?> ? metadata['version'] : null;
    if (version != null) fields['version'] = _asString(version);
  }
  return (fields: fields, body: lines.sublist(closing + 1).join('\n'));
}

String _asString(Object? value) => (value?.toString() ?? '').trim();

final RegExp _plain = RegExp(r'^[A-Za-z][A-Za-z0-9_-]*( [A-Za-z0-9_-]+)*$');
const Set<String> _reserved = {'true', 'false', 'null', 'yes', 'no', 'on', 'off', 'y', 'n'};

/// Builds a Markdown file from the frontmatter [fields] and the [body].
///
/// Values that YAML could read as something else than the same string (colons, numbers, quotes,
/// keywords) are written as double-quoted strings, so [parseFrontmatter] reads the fields back
/// unchanged.
String writeFrontmatter(Map<String, String> fields, String body) {
  final buffer = StringBuffer()..writeln(_fence);
  for (final MapEntry(:key, :value) in fields.entries) {
    final plain = _plain.hasMatch(value) && !_reserved.contains(value.toLowerCase());
    buffer.writeln('$key: ${plain ? value : jsonEncode(value)}');
  }
  buffer
    ..writeln(_fence)
    ..write(body);
  return buffer.toString();
}
