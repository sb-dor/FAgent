import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/feature/changes_pane/models/changed_file.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_handle.dart';

/// {@template changed_files_notifier}
/// The files changed in the open chat, derived from its [ChatHandle]. The files are folded again
/// only when the chat's feed is a new list, so the tab and its counter share one result.
/// {@endtemplate}
class ChangedFilesNotifier extends ValueNotifier<List<ChangedFile>> {
  /// {@macro changed_files_notifier}
  ChangedFilesNotifier({required this._handle, required this.projectRoot})
    : super(const <ChangedFile>[]) {
    _handle.addListener(_update);
    _update();
  }

  final ValueListenable<ChatHandle?> _handle;

  /// The folder paths of old journals (without a git root) are relative to; read at every update.
  final ValueGetter<String> projectRoot;

  Object? _items;

  void _update() {
    final items = _handle.value?.view.items;
    if (identical(items, _items)) return;
    _items = items;
    value = items == null
        ? const <ChangedFile>[]
        : collectChanges(items, projectRoot: projectRoot());
  }

  @override
  void dispose() {
    _handle.removeListener(_update);
    super.dispose();
  }
}
