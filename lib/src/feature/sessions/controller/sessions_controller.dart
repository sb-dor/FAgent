import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/feature/sessions/data/sessions_repository.dart';
import 'package:flutter_code_agent/src/feature/sessions/models/chat_session.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'sessions_controller.freezed.dart';

@freezed
sealed class SessionsState with _$SessionsState {
  const factory SessionsState.initial() = Sessions$InitialState;

  const factory SessionsState.inProgress() = Sessions$InProgressState;

  const factory SessionsState.error({Object? error}) = Sessions$ErrorState;

  const factory SessionsState.completed(List<ChatSession> sessions) = Sessions$CompletedState;
}

/// Keeps the chats of all projects in sync with the database, most recently active first.
final class SessionsController extends StateController<SessionsState>
    with SequentialControllerHandler {
  SessionsController({
    required this._repository,
    super.initialState = const SessionsState.initial(),
  });

  final ISessionsRepository _repository;
  StreamSubscription<List<ChatSession>>? _subscription;

  /// Starts following the chats of every project.
  void watchAll() => handle(() async {
    setState(const SessionsState.inProgress());
    await _subscription?.cancel();
    _subscription = _repository.watchAllSessions().listen(
      (sessions) => setState(SessionsState.completed(sessions)),
      onError: (Object error) => setState(SessionsState.error(error: error)),
    );
  }, error: (error, stackTrace) async => setState(SessionsState.error(error: error)));

  /// Live status of chat [sessionId], or `null` while it was not opened in
  /// this run.
  ValueListenable<SessionStatus>? statusOf(int sessionId) => _repository.statusOf(sessionId);

  @override
  void dispose() {
    _subscription?.cancel().ignore();
    super.dispose();
  }
}
