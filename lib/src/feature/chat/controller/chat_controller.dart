import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/feature/chat/data/chat_repository.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_transcript.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_controller.freezed.dart';

@freezed
sealed class ChatState with _$ChatState {
  const factory ChatState.initial() = Chat$InitialState;

  const factory ChatState.inProgress() = Chat$InProgressState;

  const factory ChatState.error({Object? error}) = Chat$ErrorState;

  const factory ChatState.completed(ChatView view) = Chat$CompletedState;
}

/// Shows one chat: folds its journal and follows its live status.
///
/// While the agent streams, the feed is folded at most every
/// [refoldInterval] instead of once per chunk.
final class ChatController extends StateController<ChatState> with SequentialControllerHandler {
  ChatController({
    required this._repository,
    this.refoldInterval = const Duration(milliseconds: 50),
    super.initialState = const ChatState.initial(),
  });

  final IChatRepository _repository;

  /// Longest delay between a journal event and the feed showing it.
  final Duration refoldInterval;

  LiveSession? _session;
  StreamSubscription<SessionEvent>? _events;
  Timer? _refold;

  void open(int sessionId) => handle(() async {
    _detach();
    setState(const ChatState.inProgress());
    final session = _session = await _repository.open(sessionId);
    _events = session.store.added.listen((_) => _scheduleRefold());
    for (final notifier in _notifiers(session)) {
      notifier.addListener(_scheduleRefold);
    }
    _emit();
  }, error: (error, stackTrace) async => setState(ChatState.error(error: error)));

  void _scheduleRefold() => _refold ??= Timer(refoldInterval, () {
    _refold = null;
    _emit();
  });

  void _emit() {
    final session = _session;
    if (session == null || isDisposed) return;
    final configOptions = ConfigOption.parseAll(session.configOptions.value);
    final mode = permissionModeOf(configOptions)?.currentValue;
    setState(
      ChatState.completed(
        ChatView(
          sessionId: session.id,
          agentId: session.agentId,
          items: ChatTranscript.fold(
            session.store.events,
            openPermissionIds: _repository.openPermissionIds(session.id),
          ),
          status: session.status.value,
          problem: session.problem.value,
          canForceStop: session.canForceStop.value,
          canRetryPrompt: session.canRetryPrompt.value,
          configOptions: configOptions,
          bypassBlocked: mode == bypassPermissionMode && !session.bypassAcknowledged.value,
        ),
      ),
    );
  }

  static List<Listenable> _notifiers(LiveSession session) => <Listenable>[
    session.status,
    session.problem,
    session.canForceStop,
    session.canRetryPrompt,
    session.configOptions,
    session.bypassAcknowledged,
  ];

  void _detach() {
    _refold?.cancel();
    _refold = null;
    _events?.cancel().ignore();
    _events = null;
    final session = _session;
    // The hub disposes the notifiers when the app closes.
    if (session != null && session.status.hasListeners) {
      for (final notifier in _notifiers(session)) {
        notifier.removeListener(_scheduleRefold);
      }
    }
    _session = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }
}
