import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/unsaved_files/unsaved_files.dart';

/// {@template unsaved_files_gate}
/// Holds a message back while the project has files unsaved in the Code view: the agent reads the
/// disk, so it would work on the old text. The chat shows [held] and lets the user save them all
/// first or send anyway.
/// {@endtemplate}
final class UnsavedFilesGate {
  /// {@macro unsaved_files_gate}
  UnsavedFilesGate({required this._files, required this._projectId}) {
    _files.addListener(_onFiles);
  }

  final IUnsavedFiles _files;
  final int _projectId;

  /// The unsaved files while a message is held; `0` when nothing is held.
  final ValueNotifier<int> held = ValueNotifier<int>(0);

  /// Sends the held message.
  Future<void> Function()? _resume;

  /// The held message is being sent: its own check must let it through.
  bool _passing = false;

  /// [saveAll] runs: files turning saved must not drop the held message it is about to send.
  bool _saving = false;

  int get _count => _files.count(projectId: _projectId);

  /// Holds the message [resume] sends when the project has unsaved files; `false` (nothing held)
  /// when it has none, or for the held message itself.
  bool hold(Future<void> Function() resume) {
    if (_passing) return false;
    final count = _count;
    if (count == 0) return false;
    _resume = resume;
    held.value = count;
    return true;
  }

  /// Saves the project's files and sends the held message once all of them are saved; otherwise it
  /// stays held.
  Future<void> saveAll() async {
    final resume = _resume;
    if (resume == null) return;
    _saving = true;
    try {
      await _files.saveAll(projectId: _projectId);
    } finally {
      _saving = false;
    }
    if (!identical(_resume, resume)) return;
    final count = _count;
    if (count > 0) {
      held.value = count;
      return;
    }
    await _pass();
  }

  /// Sends the held message as it is.
  Future<void> sendAnyway() => _pass();

  Future<void> _pass() async {
    final resume = _resume;
    _resume = null;
    held.value = 0;
    if (resume == null) return;
    _passing = true;
    try {
      await resume();
    } finally {
      _passing = false;
    }
  }

  void _onFiles() {
    if (_resume == null || _saving) return;
    final count = _count;
    if (count > 0) {
      held.value = count;
      return;
    }
    // Saved elsewhere (⌘S in the Code view): nothing to warn about; the message waits in the
    // composer for the user to send it again.
    _resume = null;
    held.value = 0;
  }

  /// Stops following the files.
  void dispose() {
    _files.removeListener(_onFiles);
    held.dispose();
  }
}
