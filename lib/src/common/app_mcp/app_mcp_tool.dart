/// The chat a request to the app's MCP server comes from: the app session and its project.
typedef AppMcpCaller = ({int sessionId, int projectId});

/// A tool of the app's MCP server.
abstract interface class AppMcpTool {
  /// The tool name the agent calls (`list_skills`, `hot_reload`, …).
  String get name;

  /// What the tool does, for the agent.
  String get description;

  /// JSON Schema of the arguments; an object schema.
  Map<String, Object?> get inputSchema;

  /// Runs the tool for [caller] with the [arguments] the agent passed.
  Future<AppMcpResult> call(AppMcpCaller caller, Map<String, Object?> arguments);
}

/// What a tool call returns to the agent.
sealed class AppMcpResult {
  const AppMcpResult();
}

/// Plain text.
final class AppMcpText extends AppMcpResult {
  /// Creates a text result.
  const AppMcpText(this.text);

  /// The text.
  final String text;
}

/// A PNG image, with an optional [caption] (for example the file it was saved to).
final class AppMcpImage extends AppMcpResult {
  /// Creates an image result.
  const AppMcpImage(this.png, {this.caption});

  /// The PNG bytes.
  final List<int> png;

  /// Text sent with the image.
  final String? caption;
}

/// A failure the agent sees as a tool error (`isError: true`). [message] is in English.
final class AppMcpError extends AppMcpResult {
  /// Creates an error result.
  const AppMcpError(this.message);

  /// What went wrong.
  final String message;
}
