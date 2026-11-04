import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/sessions/data/sessions_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_actions_controller.freezed.dart';

/// What the last rename or delete of a chat did.
@freezed
sealed class ChatActionsState with _$ChatActionsState {
  /// Nothing was done yet.
  const factory ChatActionsState.idle() = ChatActions$IdleState;

  /// A rename or delete is running.
  const factory ChatActionsState.inProgress() = ChatActions$InProgressState;

  /// Chat [sessionId] was renamed.
  const factory ChatActionsState.renamed({required int sessionId}) = ChatActions$RenamedState;

  /// Chat [sessionId] was deleted.
  const factory ChatActionsState.deleted({required int sessionId}) = ChatActions$DeletedState;

  /// Chat [sessionId] was kept: its agent is working.
  const factory ChatActionsState.busy({required int sessionId}) = ChatActions$BusyState;

  /// The rename or delete failed.
  const factory ChatActionsState.failed({required Object error}) = ChatActions$FailedState;
}

/// Renames and deletes chats, one at a time.
final class ChatActionsController extends StateController<ChatActionsState>
    with SequentialControllerHandler {
  ChatActionsController({
    required this._repository,
    super.initialState = const ChatActionsState.idle(),
  });

  final ISessionsRepository _repository;

  /// Names chat [sessionId] [title]; an empty name changes nothing.
  void rename(int sessionId, String title) => handle(() async {
    setState(const ChatActionsState.inProgress());
    await _repository.rename(sessionId, title);
    setState(ChatActionsState.renamed(sessionId: sessionId));
  }, error: (error, _) async => setState(ChatActionsState.failed(error: error)));

  /// Deletes chat [sessionId] with its history; one whose agent works is kept.
  void delete(int sessionId) => handle(() async {
    setState(const ChatActionsState.inProgress());
    try {
      await _repository.delete(sessionId);
    } on ChatBusyException {
      setState(ChatActionsState.busy(sessionId: sessionId));
      return;
    }
    setState(ChatActionsState.deleted(sessionId: sessionId));
  }, error: (error, _) async => setState(ChatActionsState.failed(error: error)));
}
