import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';

/// Answers the agent's permission requests.
abstract interface class IPermissionAnswerRepository {
  /// Answers [requestId] of chat [sessionId] with [optionId]. Returns `false`
  /// when the request is no longer open.
  bool answer({required int sessionId, required String requestId, required String optionId});
}

/// AgentHub-backed [IPermissionAnswerRepository].
final class PermissionAnswerRepositoryImpl implements IPermissionAnswerRepository {
  /// Creates the repository.
  PermissionAnswerRepositoryImpl({required this._hub});

  final AgentHub _hub;

  @override
  bool answer({required int sessionId, required String requestId, required String optionId}) =>
      _hub.resolvePermission(sessionId, requestId, optionId);
}
