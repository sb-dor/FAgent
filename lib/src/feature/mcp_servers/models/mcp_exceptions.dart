/// Why an MCP server was not accepted.
enum McpServerProblem {
  /// The name is empty, too long, has other characters than `A-Za-z0-9_.-` or is reserved.
  invalidName,

  /// Another server already has this name (case-insensitively).
  duplicateName,

  /// A `stdio` server without a command.
  missingCommand,

  /// An `http` server whose URL is not an `http` or `https` URL with a host.
  invalidUrl,
}

/// A server draft that the repository refused.
final class InvalidMcpServerException implements Exception {
  /// Creates the exception for [problem].
  const InvalidMcpServerException(this.problem);

  /// What is wrong.
  final McpServerProblem problem;

  @override
  String toString() => 'InvalidMcpServerException: ${problem.name}';
}

/// A `.mcp.json` text that is not JSON or has no `mcpServers` object.
final class McpJsonException implements Exception {
  /// Creates the exception with [message].
  const McpJsonException(this.message);

  /// What is wrong with the text.
  final String message;

  @override
  String toString() => 'McpJsonException: $message';
}
