import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'agents_controller.freezed.dart';

@freezed
sealed class AgentsState with _$AgentsState {
  /// Nothing is watched yet.
  const factory AgentsState.initial() = Agents$InitialState;

  /// The current [agents].
  const factory AgentsState.completed({required List<AgentInfo> agents}) = Agents$CompletedState;

  /// Watching failed with [error]; [agents] is the last list that was known.
  const factory AgentsState.error({required Object error, required List<AgentInfo> agents}) =
      Agents$ErrorState;
}

/// Follows the agents and their state on this machine.
final class AgentsController extends StateController<AgentsState> with SequentialControllerHandler {
  AgentsController({required this._repository, super.initialState = const AgentsState.initial()});

  final IAgentsRepository _repository;
  StreamSubscription<List<AgentInfo>>? _subscription;
  List<AgentInfo> _agents = const <AgentInfo>[];

  /// The last known agents; empty before the first list arrives.
  List<AgentInfo> get agents => _agents;

  /// Starts following the agents. Calling it again changes nothing.
  void watch() => handle(() async {
    if (isDisposed || _subscription != null) return;
    _subscription = _repository.watchAgents().listen(
      (agents) => setState(AgentsState.completed(agents: _agents = agents)),
      onError: (Object error) => setState(AgentsState.error(error: error, agents: _agents)),
    );
  }, error: (error, stackTrace) async => setState(AgentsState.error(error: error, agents: _agents)));

  @override
  void dispose() {
    _subscription?.cancel().ignore();
    super.dispose();
  }
}
