import 'dart:async';

import 'package:dart_acp_sdk/dart_acp_sdk.dart' show CancellationException;
import 'package:flutter_code_agent/src/common/acp/agent_auth.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/models/custom_agent_draft.dart';

/// Claude, signed in.
const AgentInfo memoryClaudeAgent = AgentInfo(
  id: 'claude',
  name: 'Claude Code',
  version: '0.96.0',
  runtime: 'Node 22.11',
  status: AgentStatus.ready,
  account: 'a@b.c',
  methods: <AgentLoginMethod>[
    AgentLoginMethod(id: 'claude-ai-login', name: 'claude-ai-login', kind: AgentLoginKind.terminal),
    AgentLoginMethod(id: 'console-login', name: 'console-login', kind: AgentLoginKind.terminal),
  ],
  canSignOut: true,
);

/// Codex, signed out: ChatGPT in the browser, or a key that is not set.
const AgentInfo memoryCodexAgent = AgentInfo(
  id: 'codex',
  name: 'Codex',
  version: '2.5.0',
  runtime: 'Node 22.11',
  status: AgentStatus.needsLogin,
  methods: <AgentLoginMethod>[
    AgentLoginMethod(id: 'chat-gpt', name: 'Login with ChatGPT', kind: AgentLoginKind.browser),
    AgentLoginMethod(
      id: 'api-key',
      name: 'Use OPENAI_API_KEY',
      kind: AgentLoginKind.apiKey,
      keyVariables: <String>['CODEX_API_KEY', 'OPENAI_API_KEY'],
    ),
  ],
  canSignOut: true,
);

/// Gemini CLI, signed out: Google in the browser, a key that is not set, and Vertex AI.
const AgentInfo memoryGeminiAgent = AgentInfo(
  id: 'gemini',
  name: 'Gemini CLI',
  version: '0.66.0',
  runtime: 'Node 22.11',
  status: AgentStatus.needsLogin,
  methods: <AgentLoginMethod>[
    AgentLoginMethod(
      id: 'oauth-personal',
      name: 'Log in with Google',
      kind: AgentLoginKind.browser,
    ),
    AgentLoginMethod(
      id: 'gemini-api-key',
      name: 'Use Gemini API key',
      kind: AgentLoginKind.apiKey,
      keyVariables: <String>['GEMINI_API_KEY'],
    ),
    AgentLoginMethod(id: 'vertex-ai', name: 'Vertex AI', kind: AgentLoginKind.unsupported),
  ],
);

/// [IAgentsRepository] that keeps the agents in memory, for tests.
///
/// It follows the real repository: a sign-in or sign-out changes the agent's status and emits the
/// agents again, custom agents are added, changed and removed in place. It starts no process.
/// Every action is recorded in [calls], for example `logout:claude`, `login:claude:claude-ai-login`,
/// `cancelLogin:codex`, `refresh:gemini`, `addCustom:Mine`, `removeCustom:custom:1`.
///
/// With [holdSignIns] a browser or key sign-in waits until [finishSignIn] or `cancelLogin`.
class MemoryAgentsRepository implements IAgentsRepository {
  /// Creates the repository with [agents], or with a signed-in Claude and signed-out Codex and
  /// Gemini.
  MemoryAgentsRepository({List<AgentInfo>? agents, this.holdSignIns = false})
    : _agents = <AgentInfo>[
        ...agents ?? const <AgentInfo>[memoryClaudeAgent, memoryCodexAgent, memoryGeminiAgent],
      ];

  final List<AgentInfo> _agents;
  final Set<StreamController<List<AgentInfo>>> _watchers = <StreamController<List<AgentInfo>>>{};
  final Map<String, Completer<void>> _signIns = <String, Completer<void>>{};
  int _nextCustom = 1;

  /// Browser and key sign-ins wait for [finishSignIn] or `cancelLogin`.
  final bool holdSignIns;

  /// Agents whose chats are busy, for [hasBusyChats].
  final Set<String> busyAgents = <String>{};

  /// The actions called so far.
  final List<String> calls = <String>[];

  @override
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

  /// Ends the held sign-in of [agentId] successfully.
  void finishSignIn(String agentId) {
    _signIns.remove(agentId)?.complete();
    _setStatus(agentId, AgentStatus.ready);
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

  AgentInfo _agent(String agentId) =>
      _agents.where((a) => a.id == agentId).firstOrNull ??
      (throw ArgumentError.value(agentId, 'agentId', 'unknown agent'));

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
  Future<void> refreshAll() async {
    for (final agent in agents) {
      await refresh(agent.id);
    }
  }

  @override
  Future<AgentLogin?> login(String agentId, String methodId) async {
    calls.add('login:$agentId:$methodId');
    final method = _agent(agentId).methods.where((m) => m.id == methodId).firstOrNull;
    if (method == null || method.kind == AgentLoginKind.terminal) {
      final login = AgentLogin.forTest(agentId, methodId)
        ..addLine('Opening the browser to sign in')
        ..addLine('Signed in')
        ..finish(succeeded: true);
      _setStatus(agentId, AgentStatus.ready);
      return login;
    }
    if (holdSignIns) {
      final running = _signIns[agentId] ??= Completer<void>();
      await running.future;
      return null;
    }
    _setStatus(agentId, AgentStatus.ready);
    return null;
  }

  @override
  Future<void> cancelLogin(String agentId) async {
    calls.add('cancelLogin:$agentId');
    _signIns.remove(agentId)?.completeError(const CancellationException('Sign-in cancelled'));
  }

  @override
  Future<void> logout(String agentId) async {
    calls.add('logout:$agentId');
    _agent(agentId);
    _setStatus(agentId, AgentStatus.needsLogin);
  }

  @override
  Future<bool> hasBusyChats(String agentId) async => busyAgents.contains(agentId);

  @override
  Future<void> addCustom(CustomAgentDraft draft) async {
    calls.add('addCustom:${draft.name}');
    update(
      AgentInfo(
        id: 'custom:${_nextCustom++}',
        name: draft.name,
        status: AgentStatus.ready,
        source: AgentSource.custom,
        custom: draft,
      ),
    );
  }

  @override
  Future<void> updateCustom(String id, CustomAgentDraft draft) async {
    calls.add('updateCustom:$id:${draft.name}');
    update(_agent(id).copyWith(name: draft.name, custom: draft));
  }

  @override
  Future<void> removeCustom(String id) async {
    calls.add('removeCustom:$id');
    _agents.removeWhere((a) => a.id == id);
    _emit();
  }

  @override
  Future<void> openSettings(String agentId) async {
    calls.add('openSettings:$agentId');
    if (agentId != 'claude') throw ArgumentError.value(agentId, 'agentId', 'not Claude');
  }
}
