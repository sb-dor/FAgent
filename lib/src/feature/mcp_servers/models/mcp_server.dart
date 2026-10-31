import 'package:freezed_annotation/freezed_annotation.dart';

part 'mcp_server.freezed.dart';

/// How the agent talks to an MCP server.
enum McpTransport {
  /// A process the agent starts.
  stdio,

  /// A remote server at a URL.
  http,
}

/// What is known about a server's connection.
enum McpStatus {
  /// Connected.
  ready,

  /// Needs the user to sign in.
  needsAuth,

  /// Not checked yet.
  unknown,
}

/// An MCP server as the Settings screen shows it.
@freezed
abstract class McpServer with _$McpServer {
  /// Creates a server.
  const factory McpServer({
    /// `builtin:app`, `builtin:dart` or `user:<id>`.
    required String id,
    required String name,
    required McpTransport transport,

    /// The executable of a `stdio` server.
    String? command,
    @Default(<String>[]) List<String> args,
    @Default(<String, String>{}) Map<String, String> env,

    /// The address of an `http` server.
    String? url,
    @Default(<String, String>{}) Map<String, String> headers,

    /// Whether the app ships the server; it cannot be removed.
    @Default(false) bool builtin,

    /// Whether the server is on everywhere (the global switch of the user's servers).
    @Default(true) bool enabled,

    /// Ids of the projects where the server is switched off.
    @Default(<int>{}) Set<int> disabledIn,
    @Default(McpStatus.unknown) McpStatus status,

    /// How many tools the server offers; `null` when not known.
    int? toolCount,
    String? summary,

    /// Whether [status] and [toolCount] are made up until the agents connect to servers.
    @Default(true) bool isPreview,
  }) = _McpServer;
}

/// A server to add: what the user typed or what a `.mcp.json` entry holds.
@freezed
abstract class McpServerDraft with _$McpServerDraft {
  /// Creates a draft.
  const factory McpServerDraft({
    required String name,
    required McpTransport transport,
    String? command,
    @Default(<String>[]) List<String> args,
    @Default(<String, String>{}) Map<String, String> env,
    String? url,
    @Default(<String, String>{}) Map<String, String> headers,
  }) = _McpServerDraft;
}
