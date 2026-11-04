import 'dart:async';
import 'dart:io' as io;

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/code_files_repository.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_file.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:path/path.dart' as p;

part 'file_tree_controller.freezed.dart';

/// {@template file_tree_row}
/// One visible row of the explorer.
/// {@endtemplate}
@immutable
final class FileTreeRow {
  /// {@macro file_tree_row}
  const FileTreeRow({required this.node, required this.depth, required this.expanded});

  /// The entry.
  final FileNode node;

  /// 0 for an entry of the project's folder.
  final int depth;

  /// A folder whose entries are shown below it.
  final bool expanded;

  @override
  bool operator ==(Object other) =>
      other is FileTreeRow &&
      other.node == node &&
      other.depth == depth &&
      other.expanded == expanded;

  @override
  int get hashCode => Object.hash(node, depth, expanded);
}

/// What the explorer shows.
@freezed
sealed class FileTreeState with _$FileTreeState {
  /// The project's folder is being read.
  const factory FileTreeState.loading() = FileTree$LoadingState;

  /// The visible [rows], depth first.
  const factory FileTreeState.loaded({required List<FileTreeRow> rows}) = FileTree$LoadedState;

  /// The project's folder is gone.
  const factory FileTreeState.missing() = FileTree$MissingState;
}

/// The explorer of one project: which folders are open, their entries, and their changes on disk.
final class FileTreeController extends StateController<FileTreeState>
    with SequentialControllerHandler {
  /// Creates the controller for the folder [root]; [changes] are the changes under it.
  FileTreeController({
    required this._files,
    required this._root,
    required this._changes,
    super.initialState = const FileTreeState.loading(),
  });

  final ICodeFilesRepository _files;
  final String _root;
  final Stream<FileChange> _changes;
  StreamSubscription<FileChange>? _subscription;

  /// The listed entries of each folder that was read.
  final Map<String, List<FileNode>> _children = <String, List<FileNode>>{};

  /// Open folders; a folder closed under an open one keeps its own open folders, as in VS Code.
  final Set<String> _expanded = <String>{};

  /// Reads the project's folder and follows its changes.
  void load() => handle(() async {
    _subscription ??= _changes.listen(_onChange);
    if (!await _list(_root)) {
      setState(const FileTreeState.missing());
      return;
    }
    _publish();
  });

  /// Opens or closes the folder [dir].
  void toggle(String dir) => handle(() async {
    if (_expanded.remove(dir)) {
      _publish();
      return;
    }
    if (!_children.containsKey(dir) && !await _list(dir)) return;
    _expanded.add(dir);
    _publish();
  });

  /// Opens every folder between the project's folder and [path].
  void reveal(String path) => handle(() async {
    if (!p.isWithin(_root, path)) return;
    final ancestors = <String>[];
    for (var dir = p.dirname(path); p.isWithin(_root, dir); dir = p.dirname(dir)) {
      ancestors.insert(0, dir);
    }
    if (!_children.containsKey(_root) && !await _list(_root)) return;
    for (final dir in ancestors) {
      if (!_children.containsKey(dir) && !await _list(dir)) break;
      _expanded.add(dir);
    }
    _publish();
  });

  void _onChange(FileChange change) => handle(() async {
    if (change.kind == FileChangeKind.deleted) _forget(change.path);
    final parent = p.dirname(change.path);
    // Only folders on screen are read again; a closed one is read when it opens.
    if (!_children.containsKey(parent) || (parent != _root && !_expanded.contains(parent))) return;
    if (parent == _root && !await _list(_root)) {
      setState(const FileTreeState.missing());
      return;
    }
    if (parent != _root) await _list(parent);
    _publish();
  });

  /// Drops [path] and everything under it from the open and read folders.
  void _forget(String path) {
    bool under(String dir) => dir == path || p.isWithin(path, dir);
    _expanded.removeWhere(under);
    _children.removeWhere((dir, _) => under(dir));
  }

  /// Reads [dir]; `false` when it is gone or unreadable (it is then forgotten).
  Future<bool> _list(String dir) async {
    try {
      _children[dir] = await _files.list(_root, dir);
      return true;
    } on io.FileSystemException {
      _forget(dir);
      return false;
    }
  }

  void _publish() {
    final rows = <FileTreeRow>[];
    void add(String dir, int depth) {
      for (final node in _children[dir] ?? const <FileNode>[]) {
        final expanded = node.isDirectory && _expanded.contains(node.path);
        rows.add(FileTreeRow(node: node, depth: depth, expanded: expanded));
        if (expanded) add(node.path, depth + 1);
      }
    }

    add(_root, 0);
    setState(FileTreeState.loaded(rows: List<FileTreeRow>.unmodifiable(rows)));
  }

  @override
  void dispose() {
    _subscription?.cancel().ignore();
    super.dispose();
  }
}
