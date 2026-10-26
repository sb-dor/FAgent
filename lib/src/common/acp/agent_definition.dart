import 'package:meta/meta.dart';

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
  });

  /// Pinned adapter version; bumped together with app releases so the
  /// protocol never changes under a running app.
  static const String claudeAdapterVersion = '0.96.0';

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
  );

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

  @override
  String toString() => 'AgentDefinition($id)';
}
