import 'dart:io';

import 'package:flutter_code_agent/src/feature/skills/data/frontmatter.dart';
import 'package:path/path.dart' as p;

/// Copies the folder [source] to [target] with everything inside except hidden files and links.
Future<void> copyDirectory(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity in source.list()) {
    final name = p.basename(entity.path);
    if (name.startsWith('.')) continue;
    final destination = p.join(target.path, name);
    switch (entity) {
      case File():
        await entity.copy(destination);
      case Directory():
        await copyDirectory(entity, Directory(destination));
      case Link():
        break;
    }
  }
}

/// The first of `name`, `name-copy`, `name-copy-2`, … for which [exists] is `false`.
Future<String> freeName(String name, Future<bool> Function(String candidate) exists) async {
  var candidate = name;
  for (var attempt = 1; await exists(candidate); attempt++) {
    candidate = attempt == 1 ? '$name-copy' : '$name-copy-$attempt';
  }
  return candidate;
}

/// Sets the top-level `name` of the frontmatter in [text] to [name], keeping the rest as it is.
///
/// Returns [text] unchanged when it has no frontmatter or no `name` in it.
String renameFrontmatterName(String text, String name) {
  final lines = text.split('\n');
  if (lines.first.trimRight() != '---') return text;
  final replacement = writeFrontmatter({'name': name}, '').split('\n')[1];
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trimRight() == '---') break;
    if (RegExp(r'^name\s*:').hasMatch(lines[i])) {
      lines[i] = lines[i].endsWith('\r') ? '$replacement\r' : replacement;
      return lines.join('\n');
    }
  }
  return text;
}
