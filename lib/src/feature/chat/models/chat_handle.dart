import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';

/// {@template chat_handle}
/// What the workspace may use of the open chat: its latest [view] and a way to put text into
/// its composer. Published by the chat after every new view.
/// {@endtemplate}
@immutable
final class ChatHandle {
  /// {@macro chat_handle}
  const ChatHandle({required this.sessionId, required this.view, required this.insertDraft});

  /// `sessions.id` of the chat.
  final int sessionId;

  /// The chat as it is now.
  final ChatView view;

  /// Appends text to the composer (after a blank line when it already holds something), moves
  /// the caret to the end and focuses the composer.
  final void Function(String text) insertDraft;
}
