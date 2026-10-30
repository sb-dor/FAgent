import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';

/// {@template pending_chat_draft}
/// A text that waits for the chat being created to open, then goes into its composer.
///
/// The text is kept for one chat only. It is dropped when the user opens another chat before the
/// new one, or when a later chat is created without a draft.
/// {@endtemplate}
final class PendingChatDraft {
  /// {@macro pending_chat_draft}
  PendingChatDraft({required this._data});

  final WorkspaceDataController _data;
  String? _text;

  /// The chat that was selected when the draft was made; the draft is for the chat created after.
  int? _before;

  /// The chat created for the draft; `null` until it exists.
  int? _created;

  /// Keeps [text] for the chat that is about to be created; `null` drops the draft.
  void expect(String? text) {
    _text = text;
    _created = null;
    _before = _data.sessionId;
  }

  /// Drops the draft.
  void forget() => expect(null);

  /// The chat [sessionId] was created for the draft. Call before it becomes the selected chat.
  void created(int sessionId) {
    if (_text != null) _created = sessionId;
  }

  /// Call when the selection of the window changes: another chat than the new one drops the draft.
  void onSelectionChanged() {
    if (_text == null) return;
    final selected = _data.sessionId;
    if (selected != (_created ?? _before)) forget();
  }

  /// Call when the open chat publishes a handle: the new chat gets the draft.
  void onHandleChanged() {
    final text = _text;
    final handle = _data.chatHandle.value;
    if (text == null || handle == null || handle.sessionId != _created) return;
    forget();
    handle.insertDraft(text);
  }
}
