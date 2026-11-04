import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/chat_queue/queued_chats.dart';
import 'package:flutter_code_agent/src/feature/chat/models/queued_prompt.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/data/prompt_sending_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_queue_controller.freezed.dart';

/// The messages one chat sends after the agent's current turn.
@freezed
abstract class ChatQueueState with _$ChatQueueState {
  const factory ChatQueueState({
    /// The messages in the order they go.
    @Default(<QueuedPrompt>[]) List<QueuedPrompt> items,

    /// A turn ended with a failure or a stop: nothing goes until the user sends the next one.
    @Default(false) bool paused,
  }) = _ChatQueueState;
}

/// Statuses of a turn (after its setup): only a turn going from one of these to `idle` ended
/// normally. The setup of a turn reaches `idle` too, just before the turn runs.
const Set<SessionStatus> _turn = <SessionStatus>{
  SessionStatus.running,
  SessionStatus.awaitingPermission,
  SessionStatus.cancelling,
};

/// The message queue of the chat [sessionId] (in memory).
///
/// It follows the chat's status ([follow]): when a turn ends `idle` the first message goes
/// ([IPromptSendingRepository.send]), the next one after that message's turn. A turn that ends
/// with `error`, `needsAuth` or another failure, or one the user stopped ([pauseAfterStop]),
/// pauses the queue until [sendNext]. It only ever sends into its own chat.
final class ChatQueueController extends StateController<ChatQueueState> {
  ChatQueueController({
    required this.sessionId,
    required this._repository,
    super.initialState = const ChatQueueState(),
  });

  /// `sessions.id` of the chat.
  final int sessionId;

  final IPromptSendingRepository _repository;
  ValueListenable<SessionStatus>? _status;
  SessionStatus? _last;

  /// The user pressed Stop during the current turn.
  bool _stopped = false;

  /// How the last turn ended; `true` before any was seen.
  bool _lastEndedNormally = true;

  /// Follows [status], the live status of the chat. Following another one (the chat's runtime
  /// state was replaced) stops following the old; the same one changes nothing.
  void follow(ValueListenable<SessionStatus> status) {
    if (isDisposed || identical(status, _status)) return;
    _status?.removeListener(_onStatus);
    _status = status..addListener(_onStatus);
    _last = status.value;
  }

  /// Adds [prompt] at the end. When the turn it waited for is already over, it goes now (or the
  /// queue pauses, when that turn failed).
  void add(QueuedPrompt prompt) {
    if (isDisposed) return;
    setState(state.copyWith(items: <QueuedPrompt>[...state.items, prompt]));
    final status = _status?.value;
    if (status == null || status.isBusy || state.paused) return;
    if (status == SessionStatus.idle && _lastEndedNormally) {
      _sendFirst();
    } else {
      setState(state.copyWith(paused: true));
    }
  }

  /// Removes the message at [index] and returns it (to put it back into the composer); `null`
  /// when there is none.
  QueuedPrompt? edit(int index) {
    if (isDisposed || index < 0 || index >= state.items.length) return null;
    final prompt = state.items[index];
    remove(index);
    return prompt;
  }

  /// Removes the message at [index].
  void remove(int index) {
    if (isDisposed || index < 0 || index >= state.items.length) return;
    final items = <QueuedPrompt>[...state.items]..removeAt(index);
    setState(state.copyWith(items: items, paused: state.paused && items.isNotEmpty));
  }

  /// The user stopped the running turn: its end pauses the queue. Called before the status
  /// moves.
  void pauseAfterStop() {
    if (_status?.value.isBusy ?? false) _stopped = true;
  }

  /// Resumes the queue: the first message goes now when the chat can take it, else after the
  /// running turn.
  void sendNext() {
    if (isDisposed) return;
    if (state.items.isEmpty) {
      if (state.paused) setState(state.copyWith(paused: false));
      return;
    }
    setState(state.copyWith(paused: false));
    switch (_status?.value) {
      case SessionStatus.idle || SessionStatus.cold || SessionStatus.error:
        _sendFirst();
      case _:
    }
  }

  void _onStatus() {
    final status = _status;
    if (status == null || isDisposed) return;
    final previous = _last;
    final current = _last = status.value;
    if (current == SessionStatus.cancelling) _stopped = true;
    if (previous == null || !previous.isBusy || current.isBusy) return;
    // A setup that reached `idle` is not a turn: the turn it prepared runs next.
    if (current == SessionStatus.idle && !_turn.contains(previous)) return;
    final stopped = _stopped;
    _stopped = false;
    _lastEndedNormally = current == SessionStatus.idle && !stopped;
    if (state.items.isEmpty) return;
    if (!_lastEndedNormally) {
      setState(state.copyWith(paused: true));
    } else if (!state.paused) {
      _sendFirst();
    }
  }

  /// Sends the first message into this chat.
  void _sendFirst() {
    if (state.items.isEmpty) return;
    final prompt = state.items.first;
    setState(state.copyWith(items: state.items.sublist(1)));
    handle(
      () => _repository.send(sessionId, prompt.text, resources: prompt.resources),
      error: (error, stackTrace) async {
        // The chat did not take it (it was busy again): nothing was sent, so it goes back.
        // Any other failure is the chat's own (its status pauses the rest).
        if (error is StateError) {
          setState(state.copyWith(items: <QueuedPrompt>[prompt, ...state.items], paused: true));
        } else if (state.items.isNotEmpty) {
          setState(state.copyWith(paused: true));
        }
      },
    );
  }

  @override
  void dispose() {
    _status?.removeListener(_onStatus);
    _status = null;
    super.dispose();
  }
}

/// {@template chat_queue_registry}
/// The message queues of all chats, app-wide.
///
/// A chat on screen holds its queue ([acquire], [release]). A queue that still has messages
/// outlives its chat's widget, so the user can switch to another chat and the messages still go
/// into theirs when its turn ends; it is disposed once it is empty and no chat shows it.
/// {@endtemplate}
final class ChatQueueRegistry implements IQueuedChats {
  /// {@macro chat_queue_registry}
  ChatQueueRegistry({required this._create});

  /// Makes the queue of a chat.
  final ChatQueueController Function(int sessionId) _create;
  final Map<int, ChatQueueController> _queues = <int, ChatQueueController>{};
  final Map<int, int> _holders = <int, int>{};

  /// The queue of chat [sessionId], created on first use; [release] it when the chat is gone.
  ChatQueueController acquire(int sessionId) {
    _holders.update(sessionId, (count) => count + 1, ifAbsent: () => 1);
    return _queues[sessionId] ??= _create(sessionId)
      ..addListener(() => scheduleMicrotask(() => _disposeIfUnused(sessionId)));
  }

  /// The chat [sessionId] no longer shows its queue.
  void release(int sessionId) {
    final count = (_holders[sessionId] ?? 0) - 1;
    if (count > 0) {
      _holders[sessionId] = count;
      return;
    }
    _holders.remove(sessionId);
    _disposeIfUnused(sessionId);
  }

  void _disposeIfUnused(int sessionId) {
    final queue = _queues[sessionId];
    if (queue == null || _holders.containsKey(sessionId) || queue.state.items.isNotEmpty) return;
    _queues.remove(sessionId);
    queue.dispose();
  }

  @override
  Set<int> get sessionIds => <int>{
    for (final MapEntry(:key, :value) in _queues.entries)
      if (value.state.items.isNotEmpty) key,
  };

  /// Disposes every queue.
  void dispose() {
    for (final queue in _queues.values) {
      queue.dispose();
    }
    _queues.clear();
    _holders.clear();
  }
}
