import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/feature/changes_pane/models/changed_file.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_handle.dart';

/// {@template changed_files_notifier}
/// The files changed in the open chat, derived from its [ChatHandle]. The files are folded again
/// only when the chat's feed is a new list, so the tab and its counter share one result.
/// {@endtemplate}
class ChangedFilesNotifier extends ValueNotifier<List<ChangedFile>> {
  /// {@macro changed_files_notifier}
  ///
  /// [projectRoot] is read again whenever [rootChanges] notifies.
  ChangedFilesNotifier({
    required this._handle,
    required this.projectRoot,
    required this._rootChanges,
  }) : super(const <ChangedFile>[]) {
    _handle.addListener(_update);
    _rootChanges.addListener(_update);
    _update();
  }

  final ValueListenable<ChatHandle?> _handle;
  final Listenable _rootChanges;

  /// The folder paths of old journals (without a git root) are relative to, and the one tool
  /// diffs are placed in; empty while the project is not known.
  final ValueGetter<String> projectRoot;

  Object? _items;
  String? _root;

  void _update() {
    final items = _handle.value?.view.items;
    final root = projectRoot();
    if (identical(items, _items) && root == _root) return;
    _items = items;
    _root = root;
    value = items == null ? const <ChangedFile>[] : collectChanges(items, projectRoot: root);
  }

  @override
  void dispose() {
    _handle.removeListener(_update);
    _rootChanges.removeListener(_update);
    super.dispose();
  }
}
