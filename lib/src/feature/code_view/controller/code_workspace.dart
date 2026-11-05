import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_diagnostic.dart';
import 'package:flutter_code_agent/src/common/unsaved_files/unsaved_files.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_navigation_history.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_tabs_controller.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/file_tree_controller.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/code_files_repository.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/code_package_labels.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/code_view_state_repository.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/dart_analysis_repository.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

/// {@template code_workspace}
/// The Code view of one project: its explorer and its tabs, both following one watch of the
/// project's folder, and the Dart [analysis] of its open files.
/// {@endtemplate}
final class CodeWorkspace {
  /// {@macro code_workspace}
  CodeWorkspace({
    required this.projectId,
    required this.root,
    required ICodeFilesRepository files,
    required ICodeViewStateRepository state,
    this.analysis,
  }) : _files = files {
    // One watch for both; it stops once both stopped listening.
    final changes = files
        .watch(root)
        .asBroadcastStream(onCancel: (subscription) => subscription.cancel());
    tree = FileTreeController(files: files, root: root, changes: changes)..load();
    tabs = CodeTabsController(
      projectId: projectId,
      root: root,
      files: files,
      state: state,
      changes: changes,
    );
    _diagnostics = analysis?.diagnostics.listen(_onDiagnostics);
    tabs
      ..addListener(_dropClosedViews)
      ..addListener(_syncAnalysis)
      ..restore().ignore();
  }

  /// The Dart analysis of the project; `null` without one (tests).
  final IDartAnalysisRepository? analysis;

  final ICodeFilesRepository _files;

  /// Short names of files outside the project, from its `.dart_tool/package_config.json`; read
  /// once, on first use.
  Future<CodePackageLabels> get labels => _labels ??= _loadLabels();
  Future<CodePackageLabels>? _labels;

  Future<CodePackageLabels> _loadLabels() async {
    final home = io.Platform.environment['HOME'] ?? '';
    final configDir = p.join(root, '.dart_tool');
    try {
      final content = await _files.read(p.join(configDir, 'package_config.json'));
      return CodePackageLabels.parse(content.text, configDir: configDir, home: home);
    } on Object {
      return CodePackageLabels.none(home: home);
    }
  }

  /// The last diagnostics the analysis published, by file (it analyzes the whole project).
  final Map<String, List<DartDiagnostic>> _published = <String, List<DartDiagnostic>>{};
  StreamSubscription<DartFileDiagnostics>? _diagnostics;

  /// The files the analysis reports errors in.
  ValueListenable<Set<String>> get filesWithErrors => _filesWithErrors;
  final ValueNotifier<Set<String>> _filesWithErrors = ValueNotifier<Set<String>>(const <String>{});

  void _onDiagnostics(DartFileDiagnostics published) {
    _published[published.path] = published.diagnostics;
    for (final document in tabs.tabs) {
      if (document.path == published.path) document.setDiagnostics(published.diagnostics);
    }
    _filesWithErrors.value = <String>{
      for (final MapEntry(key: path, value: diagnostics) in _published.entries)
        if (diagnostics.any((d) => d.severity == DartSeverity.error)) path,
    };
  }

  /// The text each open text document had when the analysis last heard of it.
  final Map<CodeDocument, (CodeLines, VoidCallback)> _analyzed =
      <CodeDocument, (CodeLines, VoidCallback)>{};

  /// Tells the analysis about tabs that opened and closed since the last change of [tabs].
  void _syncAnalysis() {
    final analysis = this.analysis;
    if (analysis == null) return;
    final open = tabs.tabs.where((tab) => tab.kind == CodeDocumentKind.text).toSet();
    for (final document in _analyzed.keys.where((document) => !open.contains(document)).toList()) {
      final (_, listener) = _analyzed.remove(document)!;
      document.editing.removeListener(listener);
      analysis.close(document.path);
    }
    for (final document in open.where((document) => !_analyzed.containsKey(document))) {
      void listener() {
        final codeLines = document.editing.codeLines;
        final (sent, _) = _analyzed[document]!;
        // The selection moves without an edit; only new text is sent.
        if (identical(codeLines, sent)) return;
        _analyzed[document] = (codeLines, listener);
        analysis.change(document.path, document.editing.text);
      }

      _analyzed[document] = (document.editing.codeLines, listener);
      document.editing.addListener(listener);
      analysis.open(document.path, document.editing.text);
      // A file opened again shows what the analysis reported about it before.
      if (_published[document.path] case final diagnostics?) document.setDiagnostics(diagnostics);
    }
  }

  /// `projects.id`.
  final int projectId;

  /// The project's folder.
  final String root;

  /// The explorer.
  late final FileTreeController tree;

  /// The open files.
  late final CodeTabsController tabs;

  /// The places jumps left: back and forward walk them.
  final CodeNavigationHistory history = CodeNavigationHistory();

  /// The caret of the active text tab as a document position; `null` without one.
  CodePlace? get _here {
    final document = tabs.active;
    if (document == null || document.kind != CodeDocumentKind.text) return null;
    final editing = document.editing;
    final selection = editing.selection;
    final line = editing.codeLines.index2lineIndex(selection.extentIndex);
    return (
      path: document.path,
      position: LspPosition(
        line: line < 0 ? selection.extentIndex : line,
        character: selection.extentOffset,
      ),
    );
  }

  /// Opens [path] (at [at], a document position, when given) and records the place it leaves.
  ///
  /// Throws [io.PathNotFoundException] when the file does not exist; nothing is recorded then.
  Future<void> navigateTo(String path, {LspPosition? at}) async {
    final from = _here;
    await _openAt(path, at);
    if (from != null) history.record(from);
  }

  Future<void> _openAt(String path, LspPosition? at) =>
      tabs.open(path, line: at == null ? null : at.line + 1, column: at?.character ?? 0);

  /// Goes to the place the last jump left; a place whose file is gone is skipped.
  Future<void> goBack() => _walk(history.back);

  /// Goes to the place [goBack] left.
  Future<void> goForward() => _walk(history.forward);

  Future<void> _walk(CodePlace? Function(CodePlace? current) move) async {
    var current = _here;
    for (var place = move(current); place != null; place = move(current)) {
      try {
        await _openAt(place.path, place.position);
        return;
      } on io.PathNotFoundException {
        // Gone: the next one, without keeping the place left again.
        current = null;
      }
    }
  }

  final Map<CodeDocument, CodeTabView> _views = <CodeDocument, CodeTabView>{};

  /// The find and scroll state of [document]'s tab: kept while the tab is open, so switching tabs,
  /// Chat and Code, or projects brings it back as it was.
  CodeTabView viewOf(CodeDocument document) =>
      _views.putIfAbsent(document, () => CodeTabView(document));

  void _dropClosedViews() {
    final open = tabs.tabs.toSet();
    for (final document in _views.keys.where((document) => !open.contains(document)).toList()) {
      _views.remove(document)?.dispose();
    }
  }

  /// Stops both and closes the files without saving; the analysis stops in the background.
  void dispose() => close().ignore();

  /// [dispose], completing when the analysis server has stopped too.
  Future<void> close() async {
    tabs
      ..removeListener(_dropClosedViews)
      ..removeListener(_syncAnalysis);
    for (final MapEntry(key: document, value: (_, listener)) in _analyzed.entries) {
      document.editing.removeListener(listener);
    }
    _analyzed.clear();
    await _diagnostics?.cancel();
    _filesWithErrors.dispose();
    for (final view in _views.values) {
      view.dispose();
    }
    _views.clear();
    tree.dispose();
    tabs.dispose();
    history.dispose();
    await analysis?.dispose();
  }
}

/// {@template code_tab_view}
/// What the editor of one tab remembers besides the text: the find panel and the scroll position.
/// {@endtemplate}
final class CodeTabView {
  /// {@macro code_tab_view}
  CodeTabView(CodeDocument document)
    : find = CodeFindController(document.editing),
      scroll = CodeScrollController();

  /// The find panel's state.
  final CodeFindController find;

  /// The scroll position.
  final CodeScrollController scroll;

  /// Frees both.
  void dispose() {
    find.dispose();
    scroll.verticalScroller.dispose();
    scroll.horizontalScroller.dispose();
  }
}

/// {@template code_view_registry}
/// The Code view of every project opened in this run, kept while the app runs so switching
/// projects keeps their tabs, and the app-wide count of unsaved files.
/// {@endtemplate}
final class CodeViewRegistry extends ChangeNotifier implements IUnsavedFiles {
  /// {@macro code_view_registry}
  CodeViewRegistry({required this._files, required this._state, this._analysisFor});

  final ICodeFilesRepository _files;
  final ICodeViewStateRepository _state;

  /// Makes the Dart analysis of a project's folder; none when `null`.
  final IDartAnalysisRepository Function(String root)? _analysisFor;
  final Map<int, CodeWorkspace> _workspaces = <int, CodeWorkspace>{};

  /// The Code view of [projectId] if one was made in this run.
  CodeWorkspace? existing(int projectId) => _workspaces[projectId];

  /// The Code view of [projectId] in the folder [root], made on first use; a project whose
  /// folder changed gets a new one.
  CodeWorkspace workspaceFor({required int projectId, required String root}) {
    final existing = _workspaces[projectId];
    if (existing != null && existing.root == root) return existing;
    if (existing != null) _close(existing);
    final workspace = CodeWorkspace(
      projectId: projectId,
      root: root,
      files: _files,
      state: _state,
      analysis: _analysisFor?.call(root),
    );
    workspace.tabs.addListener(_onTabs);
    return _workspaces[projectId] = workspace;
  }

  int _lastCount = 0;

  void _onTabs() {
    final count = this.count();
    if (count == _lastCount) return;
    _lastCount = count;
    notifyListeners();
  }

  @override
  int count({int? projectId}) => projectId != null
      ? _workspaces[projectId]?.tabs.unsavedCount ?? 0
      : _workspaces.values.fold(0, (sum, workspace) => sum + workspace.tabs.unsavedCount);

  @override
  Future<bool> saveAll({int? projectId}) async {
    var all = true;
    for (final workspace in <CodeWorkspace>[
      if (projectId == null) ..._workspaces.values else ?_workspaces[projectId],
    ]) {
      if (!await workspace.tabs.saveAll()) all = false;
    }
    return all;
  }

  @override
  void discard(int projectId) {
    final workspace = _workspaces.remove(projectId);
    if (workspace == null) return;
    _close(workspace);
    _onTabs();
  }

  void _close(CodeWorkspace workspace) {
    workspace.tabs.removeListener(_onTabs);
    workspace.dispose();
  }

  /// Closes every workspace and waits for their analysis servers to stop (the app quits).
  Future<void> close() async {
    final workspaces = _workspaces.values.toList();
    _workspaces.clear();
    await Future.wait(<Future<void>>[for (final workspace in workspaces) _closeAsync(workspace)]);
  }

  Future<void> _closeAsync(CodeWorkspace workspace) {
    workspace.tabs.removeListener(_onTabs);
    return workspace.close();
  }

  @override
  void dispose() {
    _workspaces.values.forEach(_close);
    _workspaces.clear();
    super.dispose();
  }
}
