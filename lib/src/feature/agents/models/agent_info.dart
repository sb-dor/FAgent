import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'agent_info.freezed.dart';

/// Where an agent stands on this machine.
enum AgentStatus {
  /// The check is running.
  checking,

  /// Installed and signed in.
  ready,

  /// Installed; the user has to sign in.
  needsLogin,

  /// The agent or what it needs (for example Node.js) is missing.
  notInstalled,

  /// The agent is being installed.
  installing,
}

/// {@template agent_info}
/// One agent as the Settings screen shows it.
/// {@endtemplate}
@freezed
abstract class AgentInfo with _$AgentInfo {
  /// {@macro agent_info}
  const factory AgentInfo({
    /// Stable id (`claude`, `codex`, `gemini`).
    required String id,

    /// Name shown in the UI.
    required String name,

    /// Version of the agent (or its adapter); `null` when unknown.
    String? version,

    /// Runtime the agent runs on, for example `Node 22.11`.
    String? runtime,

    /// Where the agent stands.
    @Default(AgentStatus.checking) AgentStatus status,

    /// Email, organization or the source of the API key; `null` when the agent does not say.
    String? account,

    /// What is wrong when the agent is not installed.
    String? problem,

    /// How to fix [problem].
    String? hint,

    /// Login method ids the agent offers.
    @Default(<String>[]) List<String> loginMethods,

    /// Settings the agent reported on earlier runs (model, mode, effort, …).
    @Default(<ConfigOption>[]) List<ConfigOption> options,

    /// A stand-in until the agent is supported for real.
    @Default(false) bool isPreview,

    /// Chats can be started with this agent.
    @Default(false) bool canStartChats,
  }) = _AgentInfo;
}
