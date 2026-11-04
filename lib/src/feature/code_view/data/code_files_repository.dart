import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_file.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The files of a project for the Code view: folders, text files and changes on disk.
abstract interface class ICodeFilesRepository {
  /// The entries of [dir] under the project [root]: folders first, then files, each by name
  /// (case-insensitive). `.git`, `.dart_tool` and a `build` next to `pubspec.yaml` are left out;
  /// entries the project's `.gitignore` ignores are marked [FileNode.ignored].
  Future<List<FileNode>> list(String root, String dir);

  /// Changes under [root], without the folders [list] leaves out; changes to one path within
  /// [CodeFilesRepositoryImpl.mergeWindow] come as one. A change is [FileChangeKind.deleted] exactly
  /// when the path is gone; macOS may report a write to a new file as [FileChangeKind.created].
  Stream<FileChange> watch(String root);

  /// The text of [path] and its stamp.
  ///
  /// Throws [FileNotTextException] for a binary or non-UTF-8 file and [FileTooLargeException] for
  /// one over [CodeFilesRepositoryImpl.maxBytes].
  Future<FileContent> read(String path);

  /// The stamp of [path] now; `null` when it does not exist.
  Future<FileStamp?> stamp(String path);

  /// Writes [text] to [path] (a link's target) through a temporary file, keeping the file's mode.
  ///
  /// With [expected] set, throws [FileChangedOnDiskException] when the file on disk has another
  /// stamp (or is gone); `null` writes whatever is there. Returns the new stamp.
  Future<FileStamp> write(String path, String text, {required FileStamp? expected});
}

/// `dart:io` and `git check-ignore` backed [ICodeFilesRepository].
final class CodeFilesRepositoryImpl implements ICodeFilesRepository {
  /// Creates the repository.
  CodeFilesRepositoryImpl({required this._environment});

  final ShellEnvironment _environment;

  /// Files over this many bytes are not opened.
  static const int maxBytes = 5 * 1024 * 1024;

  /// A NUL byte in this many first bytes makes a file binary.
  static const int binaryProbeBytes = 8192;

  /// Changes to one path closer than this come as one.
  static const Duration mergeWindow = Duration(milliseconds: 100);

  @override
  Future<List<FileNode>> list(String root, String dir) async {
    final hasPubspec = io.File(p.join(dir, 'pubspec.yaml')).existsSync();
    final nodes = <FileNode>[];
    await for (final entity in io.Directory(dir).list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (hidden(name, parentHasPubspec: hasPubspec)) continue;
      final isDirectory = entity is io.Link
          ? io.FileSystemEntity.isDirectorySync(entity.path)
          : entity is io.Directory;
      nodes.add(FileNode(path: entity.path, name: name, isDirectory: isDirectory));
    }
    final ignored = await _ignored(root, nodes);
    return <FileNode>[
      for (final node in nodes)
        if (ignored.contains(node.path))
          FileNode(path: node.path, name: node.name, isDirectory: node.isDirectory, ignored: true)
        else
          node,
    ]..sort(compare);
  }

  /// Whether an entry called [name] is left out of the explorer.
  @visibleForTesting
  static bool hidden(String name, {required bool parentHasPubspec}) =>
      name == '.git' || name == '.dart_tool' || (name == 'build' && parentHasPubspec);

  /// Folders first, then by name, case-insensitively.
  @visibleForTesting
  static int compare(FileNode a, FileNode b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.name.compareTo(b.name);
  }

  /// Paths of [nodes] that `git check-ignore` reports; none outside a repository or without git.
  Future<Set<String>> _ignored(String root, List<FileNode> nodes) async {
    if (nodes.isEmpty) return const <String>{};
    final io.Process process;
    try {
      process = await io.Process.start(
        _environment.which('git') ?? 'git',
        <String>['-C', root, 'check-ignore', '-z', '--stdin'],
        environment: _environment.variables,
        includeParentEnvironment: false,
      );
    } on io.ProcessException {
      return const <String>{};
    }
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.drain<void>();
    for (final node in nodes) {
      process.stdin.add(utf8.encode('${p.relative(node.path, from: root)}\u0000'));
    }
    await process.stdin.close();
    final exitCode = await process.exitCode;
    await errors;
    // 0: some are ignored, 1: none, 128: not a repository.
    if (exitCode != 0) return const <String>{};
    return <String>{
      for (final relative in (await output).split('\u0000'))
        if (relative.isNotEmpty) p.normalize(p.join(root, relative)),
    };
  }

  @override
  Stream<FileChange> watch(String root) {
    final controller = StreamController<FileChange>();
    StreamSubscription<io.FileSystemEvent>? subscription;
    Timer? timer;
    final pending = <String, FileChangeKind>{};
    // Whether a folder holds `pubspec.yaml` (for a `build` inside it), asked once per folder.
    final pubspecs = <String, bool>{};

    bool skipped(String path) {
      final segments = p.split(p.relative(path, from: root));
      var dir = root;
      for (final segment in segments.take(segments.length - 1)) {
        final hasPubspec = pubspecs.putIfAbsent(
          dir,
          () => io.File(p.join(dir, 'pubspec.yaml')).existsSync(),
        );
        if (hidden(segment, parentHasPubspec: hasPubspec)) return true;
        dir = p.join(dir, segment);
      }
      final hasPubspec = pubspecs.putIfAbsent(
        dir,
        () => io.File(p.join(dir, 'pubspec.yaml')).existsSync(),
      );
      return hidden(segments.last, parentHasPubspec: hasPubspec);
    }

    // FSEvents piles up the flags of a path, so a write to a new file can come as a create: what
    // is on disk when the batch goes out settles whether the path is gone.
    void flush() {
      if (controller.isClosed) return;
      final changes = Map<String, FileChangeKind>.of(pending);
      pending.clear();
      for (final MapEntry(key: path, value: kind) in changes.entries) {
        final exists =
            io.FileSystemEntity.typeSync(path, followLinks: false) !=
            io.FileSystemEntityType.notFound;
        controller.add(
          FileChange(
            path: path,
            kind: !exists
                ? FileChangeKind.deleted
                : kind == FileChangeKind.deleted
                ? FileChangeKind.modified
                : kind,
          ),
        );
      }
    }

    void record(String path, FileChangeKind kind) {
      if (p.equals(path, root) || !p.isWithin(root, path) || skipped(path)) return;
      pending[path] = mergeKinds(pending[path], kind);
      timer?.cancel();
      timer = Timer(mergeWindow, flush);
    }

    controller
      ..onListen = () {
        subscription = io.Directory(root)
            .watch(recursive: true)
            .listen(
              (event) {
                switch (event) {
                  case io.FileSystemCreateEvent():
                    record(event.path, FileChangeKind.created);
                  case io.FileSystemModifyEvent():
                    record(event.path, FileChangeKind.modified);
                  case io.FileSystemDeleteEvent():
                    record(event.path, FileChangeKind.deleted);
                  case io.FileSystemMoveEvent(:final destination):
                    record(event.path, FileChangeKind.deleted);
                    if (destination != null) record(destination, FileChangeKind.created);
                }
              },
              onError: (Object error, StackTrace stackTrace) {
                if (!controller.isClosed) controller.addError(error, stackTrace);
              },
              onDone: () {
                timer?.cancel();
                flush();
                if (!controller.isClosed) controller.close().ignore();
              },
            );
      }
      ..onCancel = () async {
        timer?.cancel();
        await subscription?.cancel();
        if (!controller.isClosed) await controller.close();
      };
    return controller.stream;
  }

  /// The change [next] after [previous] within one merge window.
  @visibleForTesting
  static FileChangeKind mergeKinds(FileChangeKind? previous, FileChangeKind next) =>
      switch ((previous, next)) {
        // Still new, however often it was written.
        (FileChangeKind.created, FileChangeKind.modified) => FileChangeKind.created,
        // Replaced: an editor's save through a temporary file.
        (FileChangeKind.deleted, FileChangeKind.created) => FileChangeKind.modified,
        _ => next,
      };

  @override
  Future<FileContent> read(String path) async {
    final stat = io.FileStat.statSync(path);
    if (stat.type == io.FileSystemEntityType.notFound) {
      throw io.PathNotFoundException(path, const io.OSError('No such file or directory', 2));
    }
    if (stat.size > maxBytes) throw FileTooLargeException(path, stat.size);
    final text = await Isolate.run(() => decode(path, io.File(path).readAsBytesSync()));
    return FileContent(text: text, stamp: _stampOf(stat));
  }

  /// The text of [bytes] read from [path], or [FileNotTextException].
  @visibleForTesting
  static String decode(String path, Uint8List bytes) {
    final probe = bytes.length < binaryProbeBytes ? bytes.length : binaryProbeBytes;
    for (var i = 0; i < probe; i++) {
      if (bytes[i] == 0) throw FileNotTextException(path);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw FileNotTextException(path);
    }
  }

  @override
  Future<FileStamp?> stamp(String path) async {
    final stat = io.FileStat.statSync(path);
    return stat.type == io.FileSystemEntityType.notFound ? null : _stampOf(stat);
  }

  static FileStamp _stampOf(io.FileStat stat) =>
      FileStamp(modified: stat.modified, size: stat.size);

  @override
  Future<FileStamp> write(String path, String text, {required FileStamp? expected}) async {
    final target = await _target(path);
    final stat = io.FileStat.statSync(target);
    final exists = stat.type != io.FileSystemEntityType.notFound;
    if (expected != null) {
      final actual = exists ? _stampOf(stat) : null;
      if (actual != expected) throw FileChangedOnDiskException(path, actual);
    }
    final temp = io.File(p.join(p.dirname(target), '.${p.basename(target)}.${io.pid}.fagent-tmp'));
    try {
      await temp.writeAsString(text, flush: true);
      final mode = stat.mode & 0x1FF;
      if (exists && mode != temp.statSync().mode & 0x1FF) {
        final chmod = await io.Process.run('chmod', <String>[mode.toRadixString(8), temp.path]);
        if (chmod.exitCode != 0) {
          throw io.FileSystemException('chmod failed: ${chmod.stderr}', temp.path);
        }
      }
      await temp.rename(target);
    } on Object {
      if (temp.existsSync()) await temp.delete();
      rethrow;
    }
    return (await stamp(target))!;
  }

  /// The file a write to [path] changes: a link's target, or [path] itself.
  static Future<String> _target(String path) async {
    if (!io.FileSystemEntity.isLinkSync(path)) return path;
    try {
      return await io.File(path).resolveSymbolicLinks();
    } on io.FileSystemException {
      // A dangling link: the write creates the file it points to.
      final link = await io.Link(path).target();
      return p.isAbsolute(link) ? link : p.join(p.dirname(path), link);
    }
  }
}
