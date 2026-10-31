import 'dart:async';

import 'package:flutter_code_agent/src/common/acp/agent_auth.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agents_exceptions.dart';

/// [IAgentsRepository] that keeps the agents in memory, for tests.
///
/// It follows the real repository: [login] and [logout] change Claude's status and emit the agents
/// again, a preview agent refuses every action with an [AgentPreviewException] for `M5`. It starts no
/// process. Every action is recorded in [calls], for example `logout:claude`,
/// `login:claude:claude-ai-login`, `install:codex`, `openSettings:claude`.
final class MemoryAgentsRepository implements IAgentsRepository {
  /// Creates the repository with [agents], or with a signed-in Claude and the two preview agents.
  MemoryAgentsRepository({List<AgentInfo>? agents})
    : _agents = <AgentInfo>[
        ...agents ??
            const <AgentInfo>[
              AgentInfo(
                id: 'claude',
                name: 'Claude Code',
                version: '0.96.0',
                runtime: 'Node 22.11',
                status: AgentStatus.ready,
                account: 'a@b.c',
                loginMethods: <String>['claude-ai-login', 'console-login'],
                canStartChats: true,
              ),
              previewCodexAgent,
              previewGeminiAgent,
            ],
      ];

  final List<AgentInfo> _agents;
  final Set<StreamController<List<AgentInfo>>> _watchers = <StreamController<List<AgentInfo>>>{};

  /// The actions called so far.
  final List<String> calls = <String>[];

  /// The agents as the next watcher gets them first.
  List<AgentInfo> get agents => List<AgentInfo>.unmodifiable(_agents);

  /// How many [watchAgents] streams are listened to.
  int get activeWatchers => _watchers.length;

  /// Replaces the state of the agent with `agent.id` (or adds it) and emits.
  void update(AgentInfo agent) {
    final index = _agents.indexWhere((a) => a.id == agent.id);
    if (index < 0) {
      _agents.add(agent);
    } else {
      _agents[index] = agent;
    }
    _emit();
  }

  void _emit() {
    final snapshot = agents;
    for (final watcher in _watchers.toList()) {
      watcher.add(snapshot);
    }
  }

  void _setStatus(String agentId, AgentStatus status) {
    final index = _agents.indexWhere((a) => a.id == agentId);
    if (index < 0) return;
    _agents[index] = _agents[index].copyWith(status: status);
    _emit();
  }

  AgentInfo _claude(String agentId) {
    final agent = _agents.where((a) => a.id == agentId).firstOrNull;
    if (agent == null) throw ArgumentError.value(agentId, 'agentId', 'unknown agent');
    if (agent.isPreview) throw const AgentPreviewException('M5');
    return agent;
  }

  @override
  Stream<List<AgentInfo>> watchAgents() {
    final controller = StreamController<List<AgentInfo>>();
    controller
      ..onListen = () {
        _watchers.add(controller);
        controller.add(agents);
      }
      ..onCancel = () {
        _watchers.remove(controller);
        return controller.close();
      };
    return controller.stream;
  }

  @override
  Future<void> refresh(String agentId) async => calls.add('refresh:$agentId');

  @override
  Future<AgentLogin> login(String agentId, String methodId) async {
    calls.add('login:$agentId:$methodId');
    _claude(agentId);
    final login = AgentLogin.forTest(agentId, methodId)
      ..addLine('Opening the browser to sign in')
      ..addLine('Signed in')
      ..finish(succeeded: true);
    _setStatus(agentId, AgentStatus.ready);
    return login;
  }

  @override
  Future<void> logout(String agentId) async {
    calls.add('logout:$agentId');
    _claude(agentId);
    _setStatus(agentId, AgentStatus.needsLogin);
  }

  @override
  Future<void> install(String agentId) async {
    calls.add('install:$agentId');
    throw const AgentPreviewException('M5');
  }

  @override
  Future<void> openSettings(String agentId) async {
    calls.add('openSettings:$agentId');
    _claude(agentId);
  }
}
