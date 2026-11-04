import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/unsaved_files/unsaved_files.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_tabs_controller.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/file_tree_controller.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/code_files_repository.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/code_view_state_repository.dart';
import 'package:re_editor/re_editor.dart';

/// {@template code_workspace}
/// The Code view of one project: its explorer and its tabs, both following one watch of the
/// project's folder.
/// {@endtemplate}
final class CodeWorkspace {
  /// {@macro code_workspace}
  CodeWorkspace({
    required this.projectId,
    required this.root,
    required ICodeFilesRepository files,
    required ICodeViewStateRepository state,
  }) {
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
    tabs
      ..addListener(_dropClosedViews)
      ..restore().ignore();
  }

  /// `projects.id`.
  final int projectId;

  /// The project's folder.
  final String root;

  /// The explorer.
  late final FileTreeController tree;

  /// The open files.
  late final CodeTabsController tabs;

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

  /// Stops both and closes the files without saving.
  void dispose() {
    tabs.removeListener(_dropClosedViews);
    for (final view in _views.values) {
      view.dispose();
    }
    _views.clear();
    tree.dispose();
    tabs.dispose();
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
  CodeViewRegistry({required this._files, required this._state});

  final ICodeFilesRepository _files;
  final ICodeViewStateRepository _state;
  final Map<int, CodeWorkspace> _workspaces = <int, CodeWorkspace>{};

  /// The Code view of [projectId] in the folder [root], made on first use; a project whose
  /// folder changed gets a new one.
  CodeWorkspace workspaceFor({required int projectId, required String root}) {
    final existing = _workspaces[projectId];
    if (existing != null && existing.root == root) return existing;
    if (existing != null) _close(existing);
    final workspace = CodeWorkspace(projectId: projectId, root: root, files: _files, state: _state);
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

  @override
  void dispose() {
    _workspaces.values.forEach(_close);
    _workspaces.clear();
    super.dispose();
  }
}
