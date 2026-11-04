import 'package:meta/meta.dart';

/// {@template file_node}
/// One entry of a folder in the explorer.
/// {@endtemplate}
@immutable
final class FileNode {
  /// {@macro file_node}
  const FileNode({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.ignored = false,
  });

  /// Absolute path.
  final String path;

  /// Last segment of [path].
  final String name;

  /// A folder (a link to a folder counts as one).
  final bool isDirectory;

  /// Ignored by the project's `.gitignore`: shown dimmed.
  final bool ignored;

  @override
  bool operator ==(Object other) =>
      other is FileNode &&
      other.path == path &&
      other.isDirectory == isDirectory &&
      other.ignored == ignored;

  @override
  int get hashCode => Object.hash(path, isDirectory, ignored);

  @override
  String toString() => 'FileNode($path${isDirectory ? '/' : ''}${ignored ? ', ignored' : ''})';
}

/// {@template file_stamp}
/// What a file looked like on disk when it was read or written: a save checks it first, so a
/// change made by someone else is not overwritten unseen.
/// {@endtemplate}
@immutable
final class FileStamp {
  /// {@macro file_stamp}
  const FileStamp({required this.modified, required this.size});

  /// Last modification time.
  final DateTime modified;

  /// Size in bytes.
  final int size;

  @override
  bool operator ==(Object other) =>
      other is FileStamp && other.modified == modified && other.size == size;

  @override
  int get hashCode => Object.hash(modified, size);

  @override
  String toString() => 'FileStamp(${modified.toIso8601String()}, $size)';
}

/// {@template file_content}
/// A text file as it was read.
/// {@endtemplate}
@immutable
final class FileContent {
  /// {@macro file_content}
  const FileContent({required this.text, required this.stamp});

  /// The whole text, line endings as they are on disk.
  final String text;

  /// The file on disk when [text] was read.
  final FileStamp stamp;
}

/// What happened to a path on disk.
enum FileChangeKind {
  /// It appeared.
  created,

  /// Its content changed.
  modified,

  /// It is gone.
  deleted,
}

/// {@template file_change}
/// A change on disk under a project (the agent, git, another editor, or the app itself).
/// {@endtemplate}
@immutable
final class FileChange {
  /// {@macro file_change}
  const FileChange({required this.path, required this.kind});

  /// Absolute path.
  final String path;

  /// What happened.
  final FileChangeKind kind;

  @override
  bool operator ==(Object other) => other is FileChange && other.path == path && other.kind == kind;

  @override
  int get hashCode => Object.hash(path, kind);

  @override
  String toString() => 'FileChange(${kind.name} $path)';
}

/// The file is binary or not UTF-8: the editor does not open it.
final class FileNotTextException implements Exception {
  /// Creates the exception.
  const FileNotTextException(this.path);

  /// The file.
  final String path;

  @override
  String toString() => 'FileNotTextException($path)';
}

/// The file is larger than the editor opens.
final class FileTooLargeException implements Exception {
  /// Creates the exception.
  const FileTooLargeException(this.path, this.size);

  /// The file.
  final String path;

  /// Its size in bytes.
  final int size;

  @override
  String toString() => 'FileTooLargeException($path, $size)';
}

/// The file on disk is not what was read: a save would overwrite someone else's change.
final class FileChangedOnDiskException implements Exception {
  /// Creates the exception.
  const FileChangedOnDiskException(this.path, this.actual);

  /// The file.
  final String path;

  /// The file on disk now; `null` when it is gone.
  final FileStamp? actual;

  @override
  String toString() => 'FileChangedOnDiskException($path, $actual)';
}
