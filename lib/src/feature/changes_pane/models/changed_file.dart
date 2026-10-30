import 'dart:io';

import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/turn_files/models/file_change_kind.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// {@template changed_file}
/// A file the chat changed: what git saw ([status]) and what the agent edited ([diffs]).
/// {@endtemplate}
@immutable
final class ChangedFile {
  /// {@macro changed_file}
  const ChangedFile({required this.path, required this.status, required this.diffs});

  /// Status of a file only the agent's diffs mention (no git status for it).
  static const String edited = 'edited';

  /// Absolute, normalized path.
  final String path;

  /// A [FileChangeKind] name other than `clean` (reverted files are not listed), or [edited].
  final String status;

  /// Every diff of the agent for this file, in feed order. Empty when a command changed it.
  final List<ToolDiffContent> diffs;
}

/// The files changed in a chat's [items], the most recently changed first.
///
/// Files from `TurnFilesItem`s (relative to the git root of the turn, or to [projectRoot] in old
/// journals) and from tool diffs are one file when their paths are equal after normalizing and
/// resolving symlinks: git reports its root resolved (`/private/tmp/x`) while the agent and the
/// project use the path the user opened (`/tmp/x`). The path shown is the agent's or the
/// project's. The last git status wins, a file whose last status is `clean` was reverted and is
/// left out, and without a git status the file is [ChangedFile.edited].
///
/// Turn files of old journals (without a root) are skipped while [projectRoot] is empty: they
/// cannot be placed.
List<ChangedFile> collectChanges(List<ChatItem> items, {required String projectRoot}) {
  final resolver = _Resolver();
  final resolvedRoot = projectRoot.isEmpty
      ? null
      : resolver.resolveFolder(p.normalize(projectRoot));
  // Insertion order tracks the last change: a file touched again moves to the end.
  final entries = <String, _Entry>{};
  _Entry touch(String shown) {
    final key = resolver.resolve(shown);
    final entry = entries.remove(key) ?? _Entry(key);
    return entries[key] = entry;
  }

  for (final item in items) {
    switch (item) {
      case TurnFilesItem(:final files, :final root):
        if (root == null && projectRoot.isEmpty) continue;
        for (final file in files) {
          final path = p.normalize(p.join(root ?? projectRoot, file.path));
          if (!p.isAbsolute(path)) continue;
          touch(path).kind = fileChangeKind(file.status);
        }
      case ToolCallItem(:final diffs):
        for (final diff in diffs) {
          final path = p.normalize(p.join(projectRoot, diff.path));
          if (!p.isAbsolute(path)) continue;
          final entry = touch(path);
          entry.diffs.add(diff);
          entry.shown = path;
          // A change after the revert is not covered by the earlier status.
          if (entry.kind == FileChangeKind.clean) entry.kind = null;
        }
      default:
        break;
    }
  }

  return <ChangedFile>[
    for (final entry in entries.values.toList().reversed)
      if (entry.kind != FileChangeKind.clean)
        ChangedFile(
          path: entry.shown ?? _inProject(entry.key, projectRoot, resolvedRoot),
          status: entry.kind?.name ?? ChangedFile.edited,
          diffs: List<ToolDiffContent>.unmodifiable(entry.diffs),
        ),
  ];
}

/// [resolved] in the form of [projectRoot] when it lies inside the project, else [resolved].
String _inProject(String resolved, String projectRoot, String? resolvedRoot) {
  if (resolvedRoot == null || !p.isWithin(resolvedRoot, resolved)) return resolved;
  return p.join(p.normalize(projectRoot), p.relative(resolved, from: resolvedRoot));
}

class _Entry {
  _Entry(this.key);

  /// Normalized path with symlinks resolved: what files are compared by.
  final String key;

  /// The path of the first agent diff, which is how the user knows the file.
  String? shown;
  FileChangeKind? kind;
  final List<ToolDiffContent> diffs = <ToolDiffContent>[];
}

/// Resolves symlinks of the folder part of paths, remembering each folder: a feed has many files
/// in few folders. The file itself is not resolved (a link is its own file) and may not exist
/// (deleted), so the nearest existing ancestor is resolved and the rest appended.
class _Resolver {
  final Map<String, String> _folders = <String, String>{};

  String resolve(String path) => p.join(resolveFolder(p.dirname(path)), p.basename(path));

  /// [folder] with all its symlinks resolved.
  String resolveFolder(String folder) => _folders.putIfAbsent(folder, () {
    var existing = folder;
    final rest = <String>[];
    while (FileSystemEntity.typeSync(existing) == FileSystemEntityType.notFound) {
      final parent = p.dirname(existing);
      if (parent == existing) return folder;
      rest.add(p.basename(existing));
      existing = parent;
    }
    try {
      return p.joinAll(<String>[Directory(existing).resolveSymbolicLinksSync(), ...rest.reversed]);
    } on FileSystemException {
      return folder;
    }
  });
}
