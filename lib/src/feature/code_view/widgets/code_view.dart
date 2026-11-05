import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_range.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_navigation_controller.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_workspace.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/code_package_labels.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_file.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_analysis_footer.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_editor_view.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_explorer.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_file_bars.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_quick_open.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_references_dialog.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_tab_bar.dart';
import 'package:path/path.dart' as p;

/// {@template code_view}
/// The Code view of one project in place of the chat: the explorer, a divider that sets its width,
/// the tabs and the editor. ⌘S saves, ⌘W closes the tab and ⌘P opens a file by name.
/// {@endtemplate}
class CodeView extends StatefulWidget {
  /// {@macro code_view}
  const CodeView({
    required this.workspace,
    required this.onOpenExternally,
    required this.listFiles,
    super.key,
  });

  /// The project's explorer and tabs.
  final CodeWorkspace workspace;

  /// Opens a path in the system's default app.
  final ValueChanged<String> onOpenExternally;

  /// The project's files for ⌘P, relative to its folder.
  final Future<List<String>> Function() listFiles;

  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> {
  CodeWorkspace get _workspace => widget.workspace;

  /// The project's package names, once read: the tooltips of read-only tabs.
  CodePackageLabels? _labels;

  @override
  void initState() {
    super.initState();
    _loadLabels();
  }

  @override
  void didUpdateWidget(CodeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.workspace, widget.workspace)) {
      _labels = null;
      _loadLabels();
    }
  }

  void _loadLabels() {
    final workspace = _workspace;
    workspace.labels.then((labels) {
      if (mounted && identical(workspace, _workspace)) setState(() => _labels = labels);
    }).ignore();
  }

  String _labelFor(CodeDocument document) => document.readOnly
      ? _labels?.labelFor(document.path) ?? document.path
      : p.relative(document.path, from: _workspace.root);

  Future<void> _open(String path) async {
    try {
      await _workspace.tabs.open(path);
    } on io.PathNotFoundException {
      // Gone since the explorer listed it; the explorer drops it with the change.
    }
  }

  /// Saves [document] (the active one by default); a file changed on disk asks first.
  Future<void> _save([CodeDocument? document]) async {
    final target = document ?? _workspace.tabs.active;
    if (target == null) return;
    try {
      await target.save();
    } on FileChangedOnDiskException {
      if (!mounted) return;
      final localization = Localization.of(context);
      final overwrite = await _ask<bool>(
        title: localization.codeOverwriteQuestion,
        answers: <(bool?, String)>[(null, localization.cancel), (true, localization.codeOverwrite)],
      );
      if (overwrite ?? false) await target.save(overwrite: true);
    }
  }

  /// Closes [document] (the active one by default); unsaved edits ask first.
  Future<void> _close([CodeDocument? document]) async {
    final target = document ?? _workspace.tabs.active;
    if (target == null) return;
    if (_workspace.tabs.close(target.path)) return;
    final localization = Localization.of(context);
    final answer = await _ask<_CloseAnswer>(
      title: localization.codeSaveQuestion(p.basename(target.path)),
      answers: <(_CloseAnswer?, String)>[
        (null, localization.cancel),
        (_CloseAnswer.discard, localization.codeDontSave),
        (_CloseAnswer.save, localization.save),
      ],
    );
    switch (answer) {
      case _CloseAnswer.save:
        await _save(target);
        if (!target.dirty) _workspace.tabs.close(target.path);
      case _CloseAnswer.discard:
        _workspace.tabs.close(target.path, discard: true);
      case null:
        break;
    }
  }

  Future<void> _quickOpen() async {
    final relative = await showCodeQuickOpen(context, files: widget.listFiles);
    if (relative == null) return;
    try {
      await _workspace.navigateTo(p.join(_workspace.root, relative));
    } on io.PathNotFoundException {
      // Gone since it was listed.
    }
  }

  /// Opens what go to definition or find references found: one definition directly, the rest
  /// through the list; `false` when the chosen file is gone.
  Future<bool> _jump(CodeJump jump, {required bool references}) async {
    Future<bool> go(String path, LspPosition at) async {
      try {
        await _workspace.navigateTo(path, at: at);
        return true;
      } on io.PathNotFoundException {
        return false;
      }
    }

    if (!references && jump.locations.length == 1) {
      final location = jump.locations.single;
      return go(location.path, location.range.start);
    }
    final rows = await _workspace.referencesFor(jump.locations);
    if (!mounted) return true;
    final localization = Localization.of(context);
    final picked = await showCodeReferences(
      context,
      title: references
          ? localization.codeReferencesTitle(jump.name, rows.length)
          : localization.codeDefinitionsTitle(jump.name, rows.length),
      references: rows,
    );
    if (picked == null) return true;
    return go(picked.path, LspPosition(line: picked.line, character: picked.column));
  }

  /// A question with [answers] as buttons, the last one the default.
  Future<T?> _ask<T>({required String title, required List<(T?, String)> answers}) => showDialog<T>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
      content: Text(title),
      actions: <Widget>[
        for (final (index, (value, label)) in answers.indexed)
          if (index == answers.length - 1)
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(value),
              child: Text(label),
            )
          else
            TextButton(onPressed: () => Navigator.of(context).pop(value), child: Text(label)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () => _save().ignore(),
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () => _close().ignore(),
      const SingleActivator(LogicalKeyboardKey.keyP, meta: true): () => _quickOpen().ignore(),
      const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
          _workspace.goBack().ignore(),
      const SingleActivator(LogicalKeyboardKey.minus, control: true, shift: true): () =>
          _workspace.goForward().ignore(),
    },
    child: FocusScope(
      child: ListenableBuilder(
        listenable: _workspace.tabs,
        builder: (context, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: _workspace.tabs.explorerWidth,
              child: CodeExplorer(
                tree: _workspace.tree,
                onOpenFile: (path) => _open(path).ignore(),
                onOpenExternally: widget.onOpenExternally,
                filesWithErrors: _workspace.analysis == null ? null : _workspace.filesWithErrors,
              ),
            ),
            _Divider(
              onDrag: (delta) =>
                  _workspace.tabs.setExplorerWidth(_workspace.tabs.explorerWidth + delta),
            ),
            Expanded(child: _buildEditorArea(context)),
          ],
        ),
      ),
    ),
  );

  Widget _buildEditorArea(BuildContext context) {
    final tabs = _workspace.tabs;
    final active = tabs.active;
    if (active == null) {
      return Center(
        child: Text(
          Localization.of(context).codeEmptyHint,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colors.muted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CodeTabBar(
          tabs: tabs.tabs,
          active: active,
          labelFor: _labelFor,
          history: _workspace.history,
          onBack: () => _workspace.goBack().ignore(),
          onForward: () => _workspace.goForward().ignore(),
          onActivate: (document) => tabs.activate(document.path),
          onClose: (document) => _close(document).ignore(),
          onOpenExternally: widget.onOpenExternally,
        ),
        if (active.changedOnDisk) CodeConflictBar(document: active),
        if (active.kind == CodeDocumentKind.text && active.error != null)
          CodeErrorLine(message: active.error!),
        Expanded(
          child: switch (active.kind) {
            CodeDocumentKind.text => CodeEditorView(
              key: ObjectKey(active),
              document: active,
              find: _workspace.viewOf(active).find,
              scroll: _workspace.viewOf(active).scroll,
              onSave: () => _save(active).ignore(),
              analysis: _workspace.analysis,
              onJump: _jump,
            ),
            CodeDocumentKind.image => CodeImageView(path: active.path),
            CodeDocumentKind.notText ||
            CodeDocumentKind.tooLarge ||
            CodeDocumentKind.unreadable => CodeNotOpenable(
              document: active,
              onOpenExternally: () => widget.onOpenExternally(active.path),
            ),
          },
        ),
        if (_workspace.analysis case final analysis? when active.path.endsWith('.dart'))
          CodeAnalysisFooter(status: analysis.status, onRestart: () => analysis.restart().ignore()),
      ],
    );
  }
}

enum _CloseAnswer { save, discard }

class _Divider extends StatelessWidget {
  const _Divider({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => MouseRegion(
    key: const ValueKey<String>('code-explorer-divider'),
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      child: SizedBox(
        width: 5,
        child: Center(child: VerticalDivider(width: 1, color: context.colors.border)),
      ),
    ),
  );
}
