import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/code_files_repository.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/code_view_state_repository.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_file.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_view_state.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

/// {@template code_tabs_controller}
/// The Code view of one project: Chat or Code, the open files in tab order and the active one,
/// and the explorer's width, remembered between launches. Documents live while their tab is open.
/// {@endtemplate}
final class CodeTabsController extends ChangeNotifier {
  /// {@macro code_tabs_controller}
  CodeTabsController({
    required this._projectId,
    required this._root,
    required this._files,
    required this._state,
    required Stream<FileChange> changes,
  }) {
    // A failed watch only stops updates; the open files stay as they are.
    _subscription = changes.listen(_onChange, onError: (Object _) {});
  }

  final int _projectId;
  final String _root;
  final ICodeFilesRepository _files;
  final ICodeViewStateRepository _state;
  late final StreamSubscription<FileChange> _subscription;

  /// The explorer's width bounds.
  static const double minExplorerWidth = 180;

  /// The explorer's width bounds.
  static const double maxExplorerWidth = 480;

  /// How long after the last change the state is saved.
  static const Duration saveDelay = Duration(milliseconds: 300);

  /// The open files in tab order.
  List<CodeDocument> get tabs => List<CodeDocument>.unmodifiable(_tabs);
  final List<CodeDocument> _tabs = <CodeDocument>[];

  /// The shown file; `null` without tabs.
  CodeDocument? get active => _active;
  CodeDocument? _active;

  /// What the chat column shows.
  CodeViewMode get mode => _mode;
  CodeViewMode _mode = CodeViewMode.chat;

  /// The explorer's width.
  double get explorerWidth => _explorerWidth;
  double _explorerWidth = 240;

  /// Unsaved open files.
  int get unsavedCount => _tabs.where((tab) => tab.dirty).length;

  /// [setMode] or [setExplorerWidth] were called: [restore] keeps those over the saved ones.
  bool _modeChosen = false;
  bool _widthChosen = false;

  Timer? _saveTimer;
  bool _disposed = false;

  /// Files being opened, so two quick opens of one file make one tab.
  final Map<String, Future<CodeDocument>> _opening = <String, Future<CodeDocument>>{};

  /// Brings back the remembered mode, tabs and width; files gone since are dropped.
  Future<void> restore() async {
    final saved = await _state.load(_projectId);
    if (_disposed) return;
    // A choice made while the saved state was loading is newer than it.
    if (!_modeChosen) _mode = saved.mode;
    if (!_widthChosen) {
      _explorerWidth = saved.explorerWidth.clamp(minExplorerWidth, maxExplorerWidth);
    }
    for (final relative in saved.tabs) {
      final path = p.join(_root, relative);
      if (_tabs.any((tab) => tab.path == path)) continue;
      try {
        _add(await CodeDocument.open(path, files: _files));
      } on io.FileSystemException {
        // Gone since the last launch.
      }
      if (_disposed) return;
    }
    final active = saved.activeTab == null ? null : p.join(_root, saved.activeTab!);
    _active = _tabs.where((tab) => tab.path == active).firstOrNull ?? _tabs.lastOrNull ?? _active;
    notifyListeners();
  }

  /// Opens [path] in a tab (or the one it already has) and activates it; with [line] (1-based)
  /// the caret goes to that line at [column] (0-based, UTF-16), every fold opened. A file outside
  /// the project opens read-only.
  ///
  /// Throws [io.PathNotFoundException] when the file does not exist.
  Future<CodeDocument> open(String path, {int? line, int column = 0}) async {
    final document =
        _tabs.where((tab) => tab.path == path).firstOrNull ??
        await (_opening[path] ??=
            CodeDocument.open(path, files: _files, readOnly: !p.isWithin(_root, path)).whenComplete(
              () {
                // A block, not an arrow: `remove` returns this very future, and whenComplete would wait
                // for it.
                _opening.remove(path);
              },
            ));
    if (_disposed) return document;
    if (!_tabs.contains(document)) _add(document);
    _active = document;
    if (line != null && document.kind == CodeDocumentKind.text) {
      document.unfoldAll();
      final editing = document.editing;
      final index = (line - 1).clamp(0, editing.lineCount - 1);
      editing
        ..selection = CodeLineSelection.collapsed(
          index: index,
          offset: column.clamp(0, editing.codeLines[index].text.length),
        )
        ..makeCursorCenterIfInvisible();
    }
    _changed();
    return document;
  }

  void _add(CodeDocument document) {
    _tabs.add(document);
    document.addListener(notifyListeners);
  }

  /// Shows the open file [path].
  void activate(String path) {
    final document = _tabs.where((tab) => tab.path == path).firstOrNull;
    if (document == null || identical(document, _active)) return;
    _active = document;
    _changed();
  }

  /// Closes the tab of [path]; a tab with unsaved edits stays (and `false` is returned) unless
  /// [discard].
  bool close(String path, {bool discard = false}) {
    final index = _tabs.indexWhere((tab) => tab.path == path);
    if (index < 0) return true;
    final document = _tabs[index];
    if (document.dirty && !discard) return false;
    _tabs.removeAt(index);
    if (identical(document, _active)) {
      _active = _tabs.isEmpty ? null : _tabs[index.clamp(0, _tabs.length - 1)];
    }
    document
      ..removeListener(notifyListeners)
      ..dispose();
    _changed();
    return true;
  }

  /// Switches between the chat and the Code view.
  void setMode(CodeViewMode mode) {
    _modeChosen = true;
    if (mode == _mode) return;
    _mode = mode;
    _changed();
  }

  /// Sets the explorer's width within [minExplorerWidth] and [maxExplorerWidth].
  void setExplorerWidth(double width) {
    _widthChosen = true;
    final clamped = width.clamp(minExplorerWidth, maxExplorerWidth);
    if (clamped == _explorerWidth) return;
    _explorerWidth = clamped;
    _changed();
  }

  /// Runs before every [save] (formatting); a failure there does not stop the save.
  Future<void> Function(CodeDocument document)? beforeSave;

  /// Saves [document] after [beforeSave].
  ///
  /// Throws [FileChangedOnDiskException] as [CodeDocument.save] does.
  Future<void> save(CodeDocument document, {bool overwrite = false}) async {
    if (document.kind != CodeDocumentKind.text || document.readOnly) return;
    try {
      await beforeSave?.call(document);
    } on Object {
      // Saving matters more than formatting.
    }
    await document.save(overwrite: overwrite);
  }

  /// Saves every unsaved tab; `false` when one stays unsaved (changed on disk or a failed write).
  Future<bool> saveAll() async {
    var all = true;
    for (final document in List<CodeDocument>.of(_tabs)) {
      if (!document.dirty) continue;
      try {
        await save(document);
      } on FileChangedOnDiskException {
        all = false;
        continue;
      }
      if (document.dirty) all = false;
    }
    return all;
  }

  void _onChange(FileChange change) {
    for (final document in List<CodeDocument>.of(_tabs)) {
      if (document.path == change.path ||
          (change.kind == FileChangeKind.deleted && p.isWithin(change.path, document.path))) {
        document.onDiskChange(change.kind).ignore();
      }
    }
  }

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, _saveState);
  }

  void _saveState() {
    _saveTimer = null;
    _state
        .save(
          _projectId,
          CodeViewState(
            mode: _mode,
            tabs: <String>[
              for (final tab in _tabs)
                if (!tab.readOnly) p.relative(tab.path, from: _root),
            ],
            activeTab: _active == null || _active!.readOnly
                ? null
                : p.relative(_active!.path, from: _root),
            explorerWidth: _explorerWidth,
          ),
        )
        .ignore();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _saveState();
    }
    _subscription.cancel().ignore();
    for (final document in _tabs) {
      document
        ..removeListener(notifyListeners)
        ..dispose();
    }
    _tabs.clear();
    super.dispose();
  }
}
