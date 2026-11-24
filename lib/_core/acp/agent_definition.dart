import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Where an agent takes the app's rules and skills prompt from.
enum RulesChannel {
  /// The Claude adapter's `_meta` of `session/new` and `session/load` (`systemPrompt`,
  /// `claudeCode.options`).
  claudeMeta,

  /// The top-level `systemPrompt` param of `session/new` and `session/load` (Codex).
  systemPrompt,

  /// A resource block in the first prompt of a new session; works with any agent.
  firstMessage,
}

/// Whether an agent ships with the app or the user added it.
enum AgentSource {
  /// Defined in code.
  builtin,

  /// Added by the user and stored in the database.
  custom,
}

/// {@template agent_definition}
/// How to start one ACP agent and log in to it.
/// {@endtemplate}
@immutable
final class AgentDefinition {
  /// {@macro agent_definition}
  const AgentDefinition({
    required this.id,
    required this.displayName,
    required this.executable,
    this.arguments = const <String>[],
    this.loginArguments = const <String, List<String>>{},
    this.minimumNodeMajor,
    this.environment = const <String, String>{},
    this.rulesChannel = RulesChannel.firstMessage,
    this.keyVariables = const <String, List<String>>{},
    this.source = AgentSource.builtin,
  });

  /// Pinned adapter version; bumped together with app releases so the
  /// protocol never changes under a running app.
  static const String claudeAdapterVersion = '0.96.0';

  /// Pinned Codex adapter version.
  static const String codexAdapterVersion = '2.5.0';

  /// Pinned Gemini CLI version.
  static const String geminiCliVersion = '0.66.0';

  /// Claude Code through the ACP adapter.
  static const AgentDefinition claude = AgentDefinition(
    id: 'claude',
    displayName: 'Claude Code',
    executable: 'npx',
    arguments: <String>['-y', '@agentclientprotocol/claude-agent-acp@$claudeAdapterVersion'],
    loginArguments: <String, List<String>>{
      'claude-ai-login': <String>['--cli', 'auth', 'login', '--claudeai'],
      'console-login': <String>['--cli', 'auth', 'login', '--console'],
    },
    minimumNodeMajor: 22,
    rulesChannel: RulesChannel.claudeMeta,
  );

  /// Codex through the ACP adapter. It signs in outside the app (`codex login`) or with a key.
  static const AgentDefinition codex = AgentDefinition(
    id: 'codex',
    displayName: 'Codex',
    executable: 'npx',
    arguments: <String>['-y', '@agentclientprotocol/codex-acp@$codexAdapterVersion'],
    minimumNodeMajor: 20,
    rulesChannel: RulesChannel.systemPrompt,
    keyVariables: <String, List<String>>{
      'api-key': <String>['CODEX_API_KEY', 'OPENAI_API_KEY'],
    },
  );

  /// Gemini CLI in its ACP mode.
  static const AgentDefinition gemini = AgentDefinition(
    id: 'gemini',
    displayName: 'Gemini CLI',
    executable: 'npx',
    arguments: <String>['-y', '@google/gemini-cli@$geminiCliVersion', '--acp'],
    minimumNodeMajor: 22,
    rulesChannel: RulesChannel.firstMessage,
    keyVariables: <String, List<String>>{
      'gemini-api-key': <String>['GEMINI_API_KEY'],
    },
  );

  /// The agents that ship with the app, in the order the UI lists them.
  static const List<AgentDefinition> builtins = <AgentDefinition>[claude, codex, gemini];

  /// Stable id stored with sessions.
  final String id;

  /// Name shown in the UI.
  final String displayName;

  /// Bare name looked up on the shell `PATH`, or an absolute path.
  final String executable;

  /// Arguments that start the agent in ACP mode.
  final List<String> arguments;

  /// Login method id → arguments appended to [arguments] to run that login.
  ///
  /// Kept here because the typed `AuthMethod` of the SDK drops the terminal
  /// arguments the adapter advertises.
  final Map<String, List<String>> loginArguments;

  /// Required Node.js major version, when the agent runs on Node.
  final int? minimumNodeMajor;

  /// Extra environment variables for the agent process.
  final Map<String, String> environment;

  /// Where the agent takes the app's rules and skills prompt from.
  final RulesChannel rulesChannel;

  /// Login method id → environment variables that sign the agent in with a key instead.
  ///
  /// The app only checks whether one of them is set; it never asks for or stores a key.
  final Map<String, List<String>> keyVariables;

  /// Whether the definition is built in or the user's own.
  final AgentSource source;

  static const DeepCollectionEquality _equality = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentDefinition &&
          other.id == id &&
          other.displayName == displayName &&
          other.executable == executable &&
          _equality.equals(other.arguments, arguments) &&
          _equality.equals(other.loginArguments, loginArguments) &&
          other.minimumNodeMajor == minimumNodeMajor &&
          _equality.equals(other.environment, environment) &&
          other.rulesChannel == rulesChannel &&
          _equality.equals(other.keyVariables, keyVariables) &&
          other.source == source;

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    executable,
    _equality.hash(arguments),
    _equality.hash(loginArguments),
    minimumNodeMajor,
    _equality.hash(environment),
    rulesChannel,
    _equality.hash(keyVariables),
    source,
  );

  @override
  String toString() => 'AgentDefinition($id)';
}
