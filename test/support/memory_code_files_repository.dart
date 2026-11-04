import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_code_agent/src/feature/code_view/data/code_files_repository.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_file.dart';
import 'package:path/path.dart' as p;

/// [ICodeFilesRepository] in memory: [files] (absolute path → text) and [folders], with a stamp per
/// file that changes on every write. Outside changes are made with [put] and [remove], which also
/// report them on [watch] unless told not to.
final class MemoryCodeFilesRepository implements ICodeFilesRepository {
  /// Creates the repository with [files] and [folders] (parents of files exist without listing).
  MemoryCodeFilesRepository({
    Map<String, String>? files,
    Set<String>? folders,
    Set<String>? ignored,
    Set<String>? notText,
    Set<String>? tooLarge,
  }) : files = <String, String>{...?files},
       folders = <String>{...?folders},
       ignored = <String>{...?ignored},
       notText = <String>{...?notText},
       tooLarge = <String>{...?tooLarge} {
    for (final path in this.files.keys) {
      stamps[path] = _nextStamp(this.files[path]!);
    }
  }

  /// Text files by absolute path.
  final Map<String, String> files;

  /// Folders by absolute path.
  final Set<String> folders;

  /// Paths `.gitignore` ignores.
  final Set<String> ignored;

  /// Files [read] refuses as binary.
  final Set<String> notText;

  /// Files [read] refuses as too large.
  final Set<String> tooLarge;

  /// The stamp of each file.
  final Map<String, FileStamp> stamps = <String, FileStamp>{};

  /// What [write] throws next, once.
  Exception? writeError;

  /// Folders [list] was asked for, in order.
  final List<String> listed = <String>[];

  /// Every write through [write], in order.
  final List<(String, String)> writes = <(String, String)>[];

  final StreamController<FileChange> _changes = StreamController<FileChange>.broadcast();

  /// Whether anyone listens to [watch].
  bool get watched => _changes.hasListener;

  int _clock = 0;

  FileStamp _nextStamp(String text) =>
      FileStamp(modified: DateTime.fromMillisecondsSinceEpoch(++_clock * 1000), size: text.length);

  bool _isFolder(String path) =>
      folders.contains(path) ||
      files.keys.any((file) => p.isWithin(path, file)) ||
      folders.any((folder) => p.isWithin(path, folder));

  /// Writes [text] to [path] from outside the app and reports it unless [notify] is false.
  void put(String path, String text, {bool notify = true}) {
    final created = !files.containsKey(path);
    files[path] = text;
    stamps[path] = _nextStamp(text);
    if (notify) emit(path, created ? FileChangeKind.created : FileChangeKind.modified);
  }

  /// Creates the folder [path] from outside and reports it.
  void putFolder(String path, {bool notify = true}) {
    folders.add(path);
    if (notify) emit(path, FileChangeKind.created);
  }

  /// Deletes [path] (a file or a folder with everything in it) and reports it.
  void remove(String path, {bool notify = true}) {
    files.removeWhere((file, _) => file == path || p.isWithin(path, file));
    stamps.removeWhere((file, _) => file == path || p.isWithin(path, file));
    folders.removeWhere((folder) => folder == path || p.isWithin(path, folder));
    if (notify) emit(path, FileChangeKind.deleted);
  }

  /// Reports a change on [watch].
  void emit(String path, FileChangeKind kind) => _changes.add(FileChange(path: path, kind: kind));

  @override
  Future<List<FileNode>> list(String root, String dir) async {
    listed.add(dir);
    if (!_isFolder(dir)) {
      throw io.PathNotFoundException(dir, const io.OSError('No such file or directory', 2));
    }
    final children = <String>{
      for (final path in <String>[...files.keys, ...folders])
        if (p.isWithin(dir, path)) p.join(dir, p.split(p.relative(path, from: dir)).first),
    };
    return <FileNode>[
      for (final path in children)
        FileNode(
          path: path,
          name: p.basename(path),
          isDirectory: !files.containsKey(path),
          ignored: ignored.contains(path),
        ),
    ]..sort(CodeFilesRepositoryImpl.compare);
  }

  @override
  Stream<FileChange> watch(String root) =>
      _changes.stream.where((change) => p.isWithin(root, change.path));

  @override
  Future<FileContent> read(String path) async {
    if (notText.contains(path)) throw FileNotTextException(path);
    if (tooLarge.contains(path)) throw FileTooLargeException(path, 6 * 1024 * 1024);
    final text = files[path];
    if (text == null) {
      throw io.PathNotFoundException(path, const io.OSError('No such file or directory', 2));
    }
    return FileContent(text: text, stamp: stamps[path]!);
  }

  @override
  Future<FileStamp?> stamp(String path) async => stamps[path];

  @override
  Future<FileStamp> write(String path, String text, {required FileStamp? expected}) async {
    if (writeError case final error?) {
      writeError = null;
      throw error;
    }
    if (expected != null && stamps[path] != expected) {
      throw FileChangedOnDiskException(path, stamps[path]);
    }
    final created = !files.containsKey(path);
    files[path] = text;
    final stamp = stamps[path] = _nextStamp(text);
    writes.add((path, text));
    // The real watch reports the app's own writes too.
    emit(path, created ? FileChangeKind.created : FileChangeKind.modified);
    return stamp;
  }

  /// Closes [watch].
  Future<void> close() => _changes.close();
}
