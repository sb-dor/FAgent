import 'package:dart_acp_sdk/dart_acp_sdk.dart' show McpServer;
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:meta/meta.dart';

/// The URI of the rules resource in the first prompt of a new agent session
/// ([RulesChannel.firstMessage]).
const String rulesResourceUri = 'flutter-agent://rules';

/// The prompt block that carries [rules] to an agent on the [RulesChannel.firstMessage] channel.
Map<String, Object?> rulesResource(String rules) => <String, Object?>{
  'type': 'resource',
  'resource': <String, Object?>{
    'uri': rulesResourceUri,
    'mimeType': 'text/markdown',
    'text': rules,
  },
};

/// Whether the prompt [block] is a [rulesResource].
bool isRulesResource(Map<String, Object?> block) =>
    block['type'] == 'resource' &&
    switch (block['resource']) {
      final Map<Object?, Object?> resource => resource['uri'] == rulesResourceUri,
      _ => false,
    };

/// What an agent session starts with besides its folder: the MCP servers it connects to and the
/// app's rules, on the agent's [RulesChannel].
@immutable
final class SessionContext {
  /// Creates a context.
  const SessionContext({
    required this.servers,
    this.meta,
    this.systemPrompt,
    this.firstMessageRules,
    this.skippedServers = const <String>[],
  });

  /// A session without servers and without rules.
  static const SessionContext empty = SessionContext(servers: <McpServer>[]);

  /// The servers of `mcpServers`, in order.
  final List<McpServer> servers;

  /// The `_meta` of `session/new` and `session/load` ([RulesChannel.claudeMeta]); `null` sends
  /// none.
  final Map<String, Object?>? meta;

  /// Rules for the top-level `systemPrompt` param of `session/new` and `session/load`
  /// ([RulesChannel.systemPrompt]); `null` sends none.
  final String? systemPrompt;

  /// Rules for the first prompt of a new agent session, as a [rulesResource]
  /// ([RulesChannel.firstMessage]); `null` adds none.
  final String? firstMessageRules;

  /// Names of the servers left out because the agent does not support their transport.
  final List<String> skippedServers;

  @override
  String toString() =>
      'SessionContext(${servers.length} servers, meta: ${meta != null}, '
      'systemPrompt: ${systemPrompt != null}, firstMessageRules: ${firstMessageRules != null}, '
      'skipped: $skippedServers)';
}

/// The context of the chat [sessionId] that runs [agent]; read on every `session/new` and
/// `session/load`. [initializeResult] is the raw `initialize` result of the agent's live
/// connection (`agentCapabilities`, …).
typedef SessionContextProvider = Future<SessionContext> Function(
  int sessionId,
  AgentDefinition agent,
  Map<String, Object?> initializeResult,
);
