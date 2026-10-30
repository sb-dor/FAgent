import 'dart:io' as io;
import 'dart:isolate';

import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Lists the files of a project for `@` mentions.
abstract interface class IProjectFilesRepository {
  /// Paths relative to [root], at most [limit] of them.
  Future<List<String>> list(String root, {int limit});

  /// Those of [paths] (relative to [root]) that exist and, with links
  /// resolved, stay inside [root]. A tracked link to `~/.ssh` is dropped.
  Future<List<String>> insideProject(String root, List<String> paths);
}

/// Uses `git ls-files` (tracked plus untracked, without ignored files) and
/// walks the folder when it is not a git repository.
final class ProjectFilesRepositoryImpl implements IProjectFilesRepository {
  /// Creates the repository.
  ProjectFilesRepositoryImpl({required this._environment});

  final ShellEnvironment _environment;

  /// Folders a walk never enters.
  @visibleForTesting
  static const Set<String> skippedFolders = <String>{
    '.git',
    '.dart_tool',
    '.idea',
    '.gradle',
    'build',
    'node_modules',
    'Pods',
  };

  @override
  Future<List<String>> list(String root, {int limit = 5000}) async {
    final io.ProcessResult result;
    try {
      result = await io.Process.run(
        _environment.which('git') ?? 'git',
        <String>['-C', root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
        environment: _environment.variables,
        includeParentEnvironment: false,
      );
    } on io.ProcessException {
      // No git on this machine.
      return Isolate.run(() => walk(root, limit: limit));
    }
    if (result.exitCode != 0) return Isolate.run(() => walk(root, limit: limit));
    final output = '${result.stdout}';
    return Isolate.run(() => parseLsFiles(output, limit: limit));
  }

  @override
  Future<List<String>> insideProject(String root, List<String> paths) async {
    final String canonicalRoot;
    try {
      canonicalRoot = await io.Directory(root).resolveSymbolicLinks();
    } on io.FileSystemException {
      return const <String>[];
    }
    final inside = <String>[];
    for (final path in paths) {
      try {
        final resolved = await io.File(p.join(root, path)).resolveSymbolicLinks();
        if (p.isWithin(canonicalRoot, resolved)) inside.add(path);
      } on io.FileSystemException {
        // Gone since the list was read.
      }
    }
    return inside;
  }

  /// Sorted unique paths of `git ls-files -z` output.
  @visibleForTesting
  static List<String> parseLsFiles(String output, {int limit = 5000}) {
    final files = output.split('\u0000').where((f) => f.isNotEmpty).toSet().toList()..sort();
    return files.take(limit).toList();
  }

  /// Files under [root] without following links, skipping [skippedFolders]
  /// and hidden folders.
  @visibleForTesting
  static List<String> walk(String root, {int limit = 5000}) {
    final files = <String>[];
    final pending = <io.Directory>[io.Directory(root)];
    while (pending.isNotEmpty && files.length < limit) {
      final List<io.FileSystemEntity> entries;
      try {
        entries = pending.removeLast().listSync(followLinks: false);
      } on io.FileSystemException {
        continue;
      }
      for (final entry in entries) {
        final name = p.basename(entry.path);
        if (entry is io.Directory) {
          if (!skippedFolders.contains(name) && !name.startsWith('.')) pending.add(entry);
        } else if (entry is io.File) {
          files.add(p.relative(entry.path, from: root));
        }
      }
    }
    files.sort();
    return files.take(limit).toList();
  }
}
