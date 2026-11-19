import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/chat/data/chat_repository.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_runtime.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_transcript.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_controller.freezed.dart';

@freezed
sealed class ChatState with _$ChatState {
  const factory ChatState.initial() = Chat$InitialState;

  const factory ChatState.inProgress() = Chat$InProgressState;

  const factory ChatState.error({Object? error}) = Chat$ErrorState;

  const factory ChatState.completed(ChatView view) = Chat$CompletedState;
}

/// Shows one chat: folds its journal and follows its live state.
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

  StreamSubscription<ChatRuntime>? _runtimes;

  /// The chat's latest runtime state; `null` until it is open.
  ChatRuntime? _runtime;
  Timer? _refold;

  /// Shows chat [sessionId]. With [keepView] the screen stays as it is until the chat is
  /// loaded again (its runtime state was replaced, for example after a change of its agent).
  void open(int sessionId, {bool keepView = false}) => handle(() async {
    _detach();
    if (!keepView) setState(const ChatState.inProgress());
    final opened = Completer<void>();
    _runtimes = _repository
        .watch(sessionId)
        .listen(
          (runtime) {
            _runtime = runtime;
            opened.isCompleted ? _scheduleRefold() : opened.complete();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!opened.isCompleted) {
              opened.completeError(error, stackTrace);
            } else if (!isDisposed) {
              setState(ChatState.error(error: error));
            }
          },
        );
    await opened.future;
    // The chat was just opened: it shows at once, and a fold that fails is the open's error.
    _emit();
  }, error: (error, stackTrace) async => setState(ChatState.error(error: error)));

  void _scheduleRefold() => _refold ??= Timer(refoldInterval, () {
    _refold = null;
    _emit();
  });

  void _emit() {
    final runtime = _runtime;
    if (runtime == null || isDisposed) return;
    setState(
      ChatState.completed(
        ChatView(
          sessionId: runtime.sessionId,
          agentId: runtime.agentId,
          items: ChatTranscript.fold(runtime.events, openPermissionIds: runtime.openPermissionIds),
          status: runtime.status,
          problem: runtime.problem,
          canForceStop: runtime.canForceStop,
          canRetryPrompt: runtime.canRetryPrompt,
          configOptions: runtime.configOptions,
          bypassBlocked: runtime.bypassBlocked,
          preparingTurn: runtime.preparingTurn,
          commands: runtime.commands,
        ),
      ),
    );
  }

  void _detach() {
    _refold?.cancel();
    _refold = null;
    _runtimes?.cancel().ignore();
    _runtimes = null;
    _runtime = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }
}
