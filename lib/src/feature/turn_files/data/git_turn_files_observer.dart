import 'dart:io' as io;
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// `git status` of a working tree: path → two-letter status (`??`, ` M`,
/// `R `, …). Renames are keyed by their new path.
typedef GitStatus = Map<String, String>;

/// What the observer remembers before a turn.
@immutable
final class TurnFilesSnapshot {
  /// Creates a snapshot.
  const TurnFilesSnapshot({required this.root, required this.status, required this.fingerprints});

  /// Absolute path of the working tree.
  final String root;

  /// Status before the turn.
  final GitStatus status;

  /// Fingerprints of the paths already dirty before the turn.
  final Map<String, String> fingerprints;
}

/// {@template git_turn_files_observer}
/// Lists the files a turn changed in a git repository — including changes
/// made by shell commands, hooks and formatters, which have no diff event.
///
/// Before the turn it records `git status` and a fingerprint of every path
/// that is already dirty; the turn waits for this. After the turn a path
/// counts as changed when it appeared in or disappeared from the status, its
/// status letters changed, or (still dirty) its fingerprint changed.
/// {@endtemplate}
final class GitTurnFilesObserver implements TurnObserver {
  /// {@macro git_turn_files_observer}
  GitTurnFilesObserver({required this._environment});

  final ShellEnvironment _environment;

  @override
  Future<Object?> beforeTurn(LiveSession session) => snapshot(session.cwd);

  @override
  Future<Map<String, Object?>?> afterTurn(LiveSession session, Object? beforeToken) async {
    if (beforeToken is! TurnFilesSnapshot) return null;
    final files = await changedSince(beforeToken);
    if (files.isEmpty) return null;
    return <String, Object?>{
      'files': <Object?>[
        for (final (path, status) in files) <String, Object?>{'path': path, 'status': status},
      ],
    };
  }

  /// Snapshot of [folder], or `null` when it is not inside a git work tree.
  Future<TurnFilesSnapshot?> snapshot(String folder) async {
    final root = await _gitRoot(folder);
    if (root == null) return null;
    final status = await _status(root);
    final fingerprints = await Isolate.run(() => fingerprintAll(root, status.keys.toList()));
    return TurnFilesSnapshot(root: root, status: status, fingerprints: fingerprints);
  }

  /// Paths (relative to the work tree) changed since [before], with their
  /// status letters now (`clean` when the path is no longer dirty).
  Future<List<(String, String)>> changedSince(TurnFilesSnapshot before) async {
    final after = await _status(before.root);
    final both = <String>[
      for (final path in after.keys)
        if (before.status[path] == after[path]) path,
    ];
    final fingerprints = await Isolate.run(() => fingerprintAll(before.root, both));
    final changed = <(String, String)>[
      for (final MapEntry(key: path, value: status) in after.entries)
        if (before.status[path] != status || before.fingerprints[path] != fingerprints[path])
          (path, status),
      for (final path in before.status.keys)
        if (!after.containsKey(path)) (path, 'clean'),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return changed;
  }

  Future<String?> _gitRoot(String folder) async {
    final result = await _git(folder, const <String>['rev-parse', '--show-toplevel']);
    return result.exitCode == 0 ? '${result.stdout}'.trim() : null;
  }

  Future<GitStatus> _status(String root) async {
    final result = await _git(root, const <String>[
      'status',
      '--porcelain=v1',
      '-z',
      '--untracked-files=all',
    ]);
    if (result.exitCode != 0)
      throw io.ProcessException('git', const <String>['status'], '${result.stderr}');
    return parseStatus('${result.stdout}');
  }

  Future<io.ProcessResult> _git(String folder, List<String> arguments) => io.Process.run(
    _environment.which('git') ?? 'git',
    <String>['-C', folder, ...arguments],
    environment: _environment.variables,
    includeParentEnvironment: false,
  );

  /// Parses `git status --porcelain=v1 -z` (NUL-separated; a rename is
  /// `XY new\0old\0`). Paths are never split on newlines.
  @visibleForTesting
  static GitStatus parseStatus(String output) {
    final status = <String, String>{};
    final fields = output.split('\u0000');
    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      if (field.length < 4) continue;
      final code = field.substring(0, 2);
      status[field.substring(3)] = code;
      // The original path of a rename or copy follows as its own field.
      if (code.contains('R') || code.contains('C')) i++;
    }
    return status;
  }

  /// Fingerprints [paths] under [root] without following links: regular
  /// files by SHA-256 of their content, links by their target text, anything
  /// else (directory, FIFO, device, missing) by a type marker — never opened.
  @visibleForTesting
  static Map<String, String> fingerprintAll(String root, List<String> paths) => <String, String>{
    for (final path in paths) path: _fingerprint(p.join(root, path)),
  };

  static String _fingerprint(String path) {
    try {
      return switch (io.FileSystemEntity.typeSync(path, followLinks: false)) {
        io.FileSystemEntityType.file => 'file:${sha256.convert(io.File(path).readAsBytesSync())}',
        io.FileSystemEntityType.link => 'link:${io.Link(path).targetSync()}',
        io.FileSystemEntityType.directory => 'dir',
        io.FileSystemEntityType.notFound => 'missing',
        _ => 'special',
      };
    } on io.FileSystemException catch (error) {
      return 'unreadable:${error.osError?.errorCode}';
    }
  }
}
