import 'package:freezed_annotation/freezed_annotation.dart';

part 'agent_probe_result.freezed.dart';

/// One sign-in method an agent offers in its `initialize` answer.
@freezed
abstract class AcpAuthMethod with _$AcpAuthMethod {
  /// Creates a sign-in method.
  const factory AcpAuthMethod({
    /// Id to pass to `authenticate` (`chat-gpt`, `gemini-api-key`, …).
    required String id,

    /// Name the agent gives the method.
    required String name,

    /// Longer explanation, when the agent gives one.
    String? description,

    /// `_meta['api-key'].provider` of a method that signs in with a key (`openai`, `google`).
    String? apiKeyProvider,
  }) = _AcpAuthMethod;
}

/// Sign-in state an agent reports about itself; never holds the account.
@freezed
abstract class AcpAuthStatus with _$AcpAuthStatus {
  /// Creates a status.
  const factory AcpAuthStatus({
    /// `none`, `account`, `api_key`, `external` or `gateway`.
    required String kind,

    /// Human-readable summary, for example "ChatGPT Plus".
    required String label,
  }) = _AcpAuthStatus;
}

/// {@template agent_probe_result}
/// What a short-lived ACP handshake found out about one agent.
/// {@endtemplate}
@freezed
abstract class AgentProbeResult with _$AgentProbeResult {
  /// {@macro agent_probe_result}
  const factory AgentProbeResult({
    /// `agentInfo.version`.
    String? version,

    /// Sign-in methods of the `initialize` answer.
    @Default(<AcpAuthMethod>[]) List<AcpAuthMethod> authMethods,

    /// The agent accepts HTTP MCP servers.
    @Default(false) bool mcpHttp,

    /// The agent accepts SSE MCP servers.
    @Default(false) bool mcpSse,

    /// The agent can load a saved session.
    @Default(false) bool loadSession,

    /// The agent takes a `systemPrompt` in `session/new` and `session/load`.
    @Default(false) bool systemPrompt,

    /// The agent supports ACP `logout`.
    @Default(false) bool canLogout,

    /// The agent takes image blocks in a prompt (`promptCapabilities.image`).
    @Default(false) bool image,

    /// Sign-in state the agent pushed after `initialize`; `null` when it pushes none.
    AcpAuthStatus? authStatus,

    /// One line saying why the handshake failed; `null` on success.
    String? failure,

    /// The agent or what it needs (Node.js) is missing; [notInstalledHint] says how to fix it.
    @Default(false) bool notInstalled,

    /// What is missing, as the preflight words it (names the executable or the Node.js version).
    String? notInstalledReason,

    /// Command or action that installs what is missing.
    String? notInstalledHint,
  }) = _AgentProbeResult;
}
