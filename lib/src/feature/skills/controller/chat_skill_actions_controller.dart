import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/skills/data/chat_skills_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_skill_actions_controller.freezed.dart';

@freezed
sealed class ChatSkillActionsState with _$ChatSkillActionsState {
  /// No change has been made.
  const factory ChatSkillActionsState.idle() = ChatSkillActions$IdleState;

  /// A change is being saved.
  const factory ChatSkillActionsState.processing() = ChatSkillActions$ProcessingState;

  /// The last change is saved. The result shows up in the choices observed through
  /// `ChatSkillsController`.
  const factory ChatSkillActionsState.completed() = ChatSkillActions$CompletedState;

  /// The last change failed with [error].
  const factory ChatSkillActionsState.failed({required Object error}) =
      ChatSkillActions$FailedState;
}

/// The checkboxes of the 🧩 menu: turns a skill on or off for one chat.
///
/// One change at a time: a tap during another one is dropped.
final class ChatSkillActionsController extends StateController<ChatSkillActionsState>
    with DroppableControllerHandler {
  ChatSkillActionsController({
    required this._repository,
    super.initialState = const ChatSkillActionsState.idle(),
  });

  final IChatSkillsRepository _repository;

  /// Turns [skillId] on or off for the chat [sessionId]; [projectEnabled] is its state in the
  /// chat's project.
  void set(int sessionId, String skillId, {required bool enabled, required bool projectEnabled}) =>
      handle(() async {
        setState(const ChatSkillActionsState.processing());
        await _repository.set(sessionId, skillId, enabled: enabled, projectEnabled: projectEnabled);
        setState(const ChatSkillActionsState.completed());
      }, error: (error, stackTrace) async => setState(ChatSkillActionsState.failed(error: error)));
}
