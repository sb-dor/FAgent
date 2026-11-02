import 'package:dart_acp_sdk/dart_acp_sdk.dart' show McpServer;
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:meta/meta.dart';

/// What an agent session starts with besides its folder: the MCP servers it connects to and the
/// agent-specific `_meta` of `session/new` and `session/load`.
@immutable
final class SessionContext {
  /// Creates a context.
  const SessionContext({required this.servers, this.meta});

  /// A session without servers and without `_meta`.
  static const SessionContext empty = SessionContext(servers: <McpServer>[]);

  /// The servers of `mcpServers`, in order.
  final List<McpServer> servers;

  /// The `_meta` of the request; `null` sends none.
  final Map<String, Object?>? meta;

  @override
  String toString() => 'SessionContext(${servers.length} servers, meta: ${meta != null})';
}

/// The context of the chat [sessionId] that runs [agent]; read on every `session/new` and
/// `session/load`.
typedef SessionContextProvider = Future<SessionContext> Function(
  int sessionId,
  AgentDefinition agent,
);
