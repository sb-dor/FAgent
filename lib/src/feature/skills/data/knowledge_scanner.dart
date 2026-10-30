import 'dart:io';

import 'package:flutter_code_agent/src/feature/skills/data/frontmatter.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:path/path.dart' as p;

/// The file every skill folder must have.
const String skillFileName = 'SKILL.md';

/// Path (absolute, or an asset key) to a "modified:size" fingerprint of a file.
typedef Snapshot = Map<String, String>;

/// Fingerprints every non-hidden file under `<root>/skills` and every `*.md` in `<root>/rules`.
///
/// A missing folder is empty, so the next call finds it once it appears.
Future<Snapshot> snapshotRoot(String root) async {
  final snapshot = <String, String>{};
  Future<void> add(FileSystemEntity entity, String base) async {
    if (entity is! File || p.split(p.relative(entity.path, from: base)).any(_isHidden)) return;
    try {
      final stat = entity.statSync();
      snapshot[entity.path] = '${stat.modified.microsecondsSinceEpoch}:${stat.size}';
    } on FileSystemException {
      // Deleted between the listing and the stat: the next snapshot will not have it.
    }
  }

  final skills = p.join(root, 'skills');
  final rules = p.join(root, 'rules');
  for (final (directory, recursive) in [(skills, true), (rules, false)]) {
    try {
      await for (final entity in Directory(directory).list(recursive: recursive)) {
        if (directory == rules && p.extension(entity.path) != '.md') continue;
        await add(entity, directory);
      }
    } on FileSystemException {
      // The folder does not exist (yet) or went away.
    }
  }
  return snapshot;
}

/// Reads the skills and rules of the folder [root] that [snapshot] (of [snapshotRoot]) lists.
Future<List<KnowledgeItem>> itemsFromSnapshot({
  required String root,
  required SkillSource source,
  required Snapshot snapshot,
}) async {
  final skillsDir = p.join(root, 'skills');
  final rulesDir = p.join(root, 'rules');
  final skillFiles = <String, List<String>>{};
  final rulePaths = <String>[];
  for (final path in snapshot.keys) {
    if (p.isWithin(skillsDir, path)) {
      final parts = p.split(p.relative(path, from: skillsDir));
      (skillFiles[parts.first] ??= []).add(p.joinAll(parts.skip(1)));
    } else if (p.dirname(path) == rulesDir) {
      rulePaths.add(path);
    }
  }

  final items = <KnowledgeItem>[];
  for (final MapEntry(key: name, value: files) in skillFiles.entries) {
    if (!files.contains(skillFileName)) continue;
    final folder = p.join(skillsDir, name);
    items.add(
      buildKnowledgeItem(
        kind: KnowledgeKind.skill,
        source: source,
        name: name,
        path: folder,
        text: await _readText(p.join(folder, skillFileName)),
        files: sortSkillFiles(files),
      ),
    );
  }
  for (final path in rulePaths) {
    items.add(
      buildKnowledgeItem(
        kind: KnowledgeKind.rule,
        source: source,
        name: p.basenameWithoutExtension(path),
        path: path,
        text: await _readText(path),
      ),
    );
  }
  return sortKnowledge(items);
}

/// Builds the items of the files that ship with the app; [files] is `IBuiltinKnowledge.load()`.
List<KnowledgeItem> builtinItems(Map<String, String> files) {
  final skillFiles = <String, List<String>>{};
  final items = <KnowledgeItem>[];
  for (final key in files.keys) {
    final parts = p.posix.split(key);
    if (parts.first == 'skills' && parts.length > 2) {
      (skillFiles[parts[1]] ??= []).add(p.posix.joinAll(parts.skip(2)));
    } else if (parts.first == 'rules' && parts.length == 2 && key.endsWith('.md')) {
      items.add(
        buildKnowledgeItem(
          kind: KnowledgeKind.rule,
          source: SkillSource.builtin,
          name: p.posix.basenameWithoutExtension(key),
          path: key,
          text: (text: files[key], error: null),
          readOnly: true,
        ),
      );
    }
  }
  for (final MapEntry(key: name, value: relative) in skillFiles.entries) {
    final text = files['skills/$name/$skillFileName'];
    if (text == null) continue;
    items.add(
      buildKnowledgeItem(
        kind: KnowledgeKind.skill,
        source: SkillSource.builtin,
        name: name,
        path: 'skills/$name',
        text: (text: text, error: null),
        files: sortSkillFiles(relative),
        readOnly: true,
      ),
    );
  }
  return sortKnowledge(items);
}

/// Builds an item from the [text] of its `SKILL.md` or rule file (`error` says why it is `null`).
///
/// A broken or incomplete header does not throw: the item gets its folder or file name as title and
/// the reason in [KnowledgeItem.problem].
KnowledgeItem buildKnowledgeItem({
  required KnowledgeKind kind,
  required SkillSource source,
  required String name,
  required String path,
  required ({String? text, String? error}) text,
  List<String> files = const [],
  bool readOnly = false,
}) {
  Map<String, String>? fields;
  var problem = text.error;
  if (text.text case final content?) {
    try {
      fields = parseFrontmatter(content)?.fields;
      if (fields == null) {
        problem = 'No frontmatter';
      } else if ((fields['description'] ?? '').isEmpty) {
        problem = 'No description';
      }
    } on FrontmatterException catch (error) {
      problem = error.message;
    }
  }

  final id = '${kind.name}:${source.name}:$name';
  if (problem != null || fields == null) {
    return KnowledgeItem(
      id: id,
      kind: kind,
      source: source,
      name: name,
      title: name,
      description: '',
      path: path,
      files: files,
      readOnly: readOnly,
      problem: problem,
    );
  }
  String? optional(String key) => (fields![key] ?? '').isEmpty ? null : fields[key];
  return KnowledgeItem(
    id: id,
    kind: kind,
    source: source,
    name: name,
    title: optional('name') ?? name,
    description: fields['description']!,
    whenToUse: optional('when_to_use'),
    version: optional('version'),
    path: path,
    files: files,
    readOnly: readOnly,
  );
}

/// `SKILL.md` first, then the other files alphabetically.
List<String> sortSkillFiles(List<String> files) => [...files]
  ..sort((a, b) {
    if (a == skillFileName) return b == skillFileName ? 0 : -1;
    if (b == skillFileName) return 1;
    return a.compareTo(b);
  });

/// Orders items by source (in the order of [SkillSource]), then by name.
List<KnowledgeItem> sortKnowledge(List<KnowledgeItem> items) => [...items]
  ..sort((a, b) {
    final bySource = a.source.index.compareTo(b.source.index);
    return bySource != 0 ? bySource : a.name.compareTo(b.name);
  });

bool _isHidden(String segment) => segment.startsWith('.');

Future<({String? text, String? error})> _readText(String path) async {
  try {
    return (text: await File(path).readAsString(), error: null);
  } on FileSystemException catch (error) {
    return (text: null, error: 'Cannot read the file: ${error.message}');
  } on FormatException {
    return (text: null, error: 'Cannot read the file: it is not valid UTF-8');
  }
}
