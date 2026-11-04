import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/feature/agents/models/custom_agent_draft.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'agent_info.freezed.dart';

/// Where an agent stands on this machine.
enum AgentStatus {
  /// The check is running.
  checking,

  /// Installed and signed in (or, for a custom agent, answering ACP).
  ready,

  /// Installed; the user has to sign in.
  needsLogin,

  /// The agent or what it needs (for example Node.js) is missing.
  notInstalled,

  /// The agent started but the ACP handshake failed; [AgentInfo.problem] says why.
  failed,
}

/// How a sign-in method of an agent works in the app.
enum AgentLoginKind {
  /// A login command in the terminal, its output shown by the app (Claude).
  terminal,

  /// ACP `authenticate`; the agent opens the browser.
  browser,

  /// ACP `authenticate` with a key the agent reads from its environment.
  apiKey,

  /// Set up in the agent itself (Vertex AI, gateways); the app offers no button.
  unsupported,
}

/// {@template agent_login_method}
/// One way to sign an agent in.
/// {@endtemplate}
@freezed
abstract class AgentLoginMethod with _$AgentLoginMethod {
  /// {@macro agent_login_method}
  const factory AgentLoginMethod({
    /// The id the agent knows the method by (`claude-ai-login`, `chat-gpt`, `gemini-api-key`).
    required String id,

    /// The name the agent gives it; Claude's terminal methods are named by the UI instead.
    required String name,

    /// How the method works in the app.
    required AgentLoginKind kind,

    /// For [AgentLoginKind.apiKey]: the environment variables the key is read from.
    @Default(<String>[]) List<String> keyVariables,

    /// For [AgentLoginKind.apiKey]: one of [keyVariables] is set (or none is known, so the agent
    /// is left to find its key).
    @Default(false) bool keyPresent,
  }) = _AgentLoginMethod;
}

/// {@template agent_info}
/// One agent as the Settings screen shows it.
/// {@endtemplate}
@freezed
abstract class AgentInfo with _$AgentInfo {
  /// {@macro agent_info}
  const factory AgentInfo({
    /// Stable id (`claude`, `codex`, `gemini`, `custom:<n>`).
    required String id,

    /// Name shown in the UI.
    required String name,

    /// Version of the agent (or its adapter); `null` when unknown.
    String? version,

    /// Runtime the agent runs on, for example `Node 22.11`.
    String? runtime,

    /// Where the agent stands.
    @Default(AgentStatus.checking) AgentStatus status,

    /// Email, plan or the variable of the API key; `null` when the agent does not say.
    String? account,

    /// What is wrong when the agent is not installed or failed.
    String? problem,

    /// How to fix [problem].
    String? hint,

    /// The ways to sign in the agent offers.
    @Default(<AgentLoginMethod>[]) List<AgentLoginMethod> methods,

    /// Built in, or added by the user.
    @Default(AgentSource.builtin) AgentSource source,

    /// The agent can be signed out from the app.
    @Default(false) bool canSignOut,

    /// What the user typed for a custom agent, for editing it; `null` for a built-in one.
    CustomAgentDraft? custom,

    /// Settings the agent reported on earlier runs (model, mode, effort, …).
    @Default(<ConfigOption>[]) List<ConfigOption> options,

    /// The agent takes images in a prompt. The built-in agents do; a custom one says so in its
    /// check (`promptCapabilities.image`) and counts as taking them until it is checked.
    @Default(true) bool acceptsImages,
  }) = _AgentInfo;

  const AgentInfo._();

  /// Chats can be started with this agent; one that needs a sign-in can still be picked.
  bool get canStartChats => status != AgentStatus.notInstalled && status != AgentStatus.failed;

  /// The app cannot tell whether a custom agent is signed in; the first chat finds out.
  bool get signInCheckedInChat => source == AgentSource.custom && status == AgentStatus.ready;
}
