import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/chat/data/chat_repository.dart';
import 'package:l/l.dart';

/// Follows the sign-in methods of every agent (agent id → methods), so the chat's sign-in banner
/// shows an agent's methods as soon as its check finds them.
final class ChatLoginMethodsController extends StateController<Map<String, List<AgentLoginMethod>>>
    with SequentialControllerHandler {
  ChatLoginMethodsController({
    required this._repository,
    super.initialState = const <String, List<AgentLoginMethod>>{},
  });

  final IChatRepository _repository;
  StreamSubscription<Map<String, List<AgentLoginMethod>>>? _subscription;

  /// The methods of [agentId]; empty while it is not checked or unknown.
  List<AgentLoginMethod> methodsOf(String agentId) => state[agentId] ?? const <AgentLoginMethod>[];

  /// Starts following the methods. Calling it again changes nothing.
  void watch() => handle(() async {
    if (isDisposed || _subscription != null) return;
    _subscription = _repository.watchLoginMethods().listen(
      setState,
      onError: (Object error, StackTrace stackTrace) =>
          l.w('Chat | the sign-in methods failed: $error', stackTrace),
    );
  });

  @override
  void dispose() {
    _subscription?.cancel().ignore();
    super.dispose();
  }
}
