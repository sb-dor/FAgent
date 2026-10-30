import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/permission_request/data/permission_answer_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'permission_answer_controller.freezed.dart';

@freezed
sealed class PermissionAnswerState with _$PermissionAnswerState {
  const factory PermissionAnswerState.initial() = PermissionAnswer$InitialState;

  const factory PermissionAnswerState.inProgress() = PermissionAnswer$InProgressState;

  const factory PermissionAnswerState.error({Object? error}) = PermissionAnswer$ErrorState;

  /// [accepted] is `false` when the request was already closed (a late click).
  const factory PermissionAnswerState.completed({required bool accepted}) =
      PermissionAnswer$CompletedState;
}

/// Sends the user's choice on a permission card; double clicks are dropped.
final class PermissionAnswerController extends StateController<PermissionAnswerState>
    with DroppableControllerHandler {
  PermissionAnswerController({
    required this._repository,
    super.initialState = const PermissionAnswerState.initial(),
  });

  final IPermissionAnswerRepository _repository;

  void answer({required int sessionId, required String requestId, required String optionId}) =>
      handle(() async {
        setState(const PermissionAnswerState.inProgress());
        final accepted = _repository.answer(
          sessionId: sessionId,
          requestId: requestId,
          optionId: optionId,
        );
        setState(PermissionAnswerState.completed(accepted: accepted));
      }, error: (error, stackTrace) async => setState(PermissionAnswerState.error(error: error)));
}
