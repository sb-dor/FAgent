import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/skills/data/chat_skills_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_skills_controller.freezed.dart';

@freezed
sealed class ChatSkillsState with _$ChatSkillsState {
  /// Nothing has arrived yet.
  const factory ChatSkillsState.initial() = ChatSkills$InitialState;

  /// The chat's [states] by skill id: only the skills that differ from the project.
  const factory ChatSkillsState.completed({required Map<String, bool> states}) =
      ChatSkills$CompletedState;

  /// Watching failed with [error]; [states] is the last choice that was known.
  const factory ChatSkillsState.error({required Object error, required Map<String, bool> states}) =
      ChatSkills$ErrorState;
}

/// Follows which skills one chat turned on or off against its project.
final class ChatSkillsController extends StateController<ChatSkillsState>
    with SequentialControllerHandler {
  ChatSkillsController({
    required this._repository,
    super.initialState = const ChatSkillsState.initial(),
  });

  final IChatSkillsRepository _repository;
  StreamSubscription<Map<String, bool>>? _subscription;
  Map<String, bool> _states = const <String, bool>{};

  /// The last known choices; empty before the first ones arrive.
  Map<String, bool> get states => _states;

  /// Starts following the choices of the chat [sessionId]. Calling it again changes nothing.
  void watch(int sessionId) => handle(
    () async {
      if (isDisposed || _subscription != null) return;
      _subscription = _repository
          .watch(sessionId)
          .listen(
            (states) => setState(ChatSkillsState.completed(states: _states = states)),
            onError: (Object error) =>
                setState(ChatSkillsState.error(error: error, states: _states)),
          );
    },
    error: (error, stackTrace) async =>
        setState(ChatSkillsState.error(error: error, states: _states)),
  );

  @override
  void dispose() {
    _subscription?.cancel().ignore();
    super.dispose();
  }
}
