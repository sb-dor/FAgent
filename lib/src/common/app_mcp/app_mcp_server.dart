import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tokens.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tool.dart';
import 'package:l/l.dart' hide LogLevel;
import 'package:mcp_dart/mcp_dart.dart';

/// The name agents know the app's MCP server by (their tools are `mcp__flutter_code_agent__*`).
const String appMcpServerName = 'flutter_code_agent';

/// The server's `instructions` for the agent. Claude Code keeps only the first 2048 characters.
const String appMcpInstructions =
    'flutter_code_agent is the MCP server of Flutter Code Agent, the desktop app this chat runs '
    'in. Its tools work on the project of this chat and on the app run shown in the Run tab.\n'
    '\n'
    'Skills: when a task may match a skill, call list_skills, then call load_skill with its name '
    'before following it. read_skill_file reads the other files a skill refers to.\n'
    '\n'
    'Running app: app_status reports the device, the mode, the run state and the VM service, DTD '
    'and DevTools URIs. To use the Dart MCP server on the running app, take the DTD URI from '
    'app_status and pass it to the dtd tool (command connect, uri).\n'
    '\n'
    'After editing code while an app is running, call hot_reload (hot_restart when the change '
    'needs a restart, for example new state initializers or main). app_logs and runtime_errors '
    'show what the app printed and the errors it hit; screenshot captures its screen. Runs '
    'belong to the Run tab: do not start or stop the app yourself.';

/// The app's own MCP server, which the agents of the chats connect to.
abstract interface class IAppMcpServer {
  /// Starts listening. Never throws: a failure is kept in [startError].
  Future<void> start();

  /// Where the server listens (`http://127.0.0.1:<port>/mcp`), or null when it is not running.
  Uri? get url;

  /// The number of tools the server offers.
  int get toolCount;

  /// Why [start] failed, or null.
  Object? get startError;

  /// Stops listening and ends every MCP session.
  Future<void> close();
}

/// Binds [server] to its port; replaced in tests.
typedef AppMcpBind = Future<void> Function(StreamableMcpServer server);

/// [IAppMcpServer] over Streamable HTTP on the loopback interface.
///
/// Every HTTP request needs `Authorization: Bearer <token>` with a token of [AppMcpTokens] whose
/// chat still exists; others get 401. An MCP session belongs to the chat whose token made its
/// first request after `initialize`: tool calls in it run for that chat, and the tokens of other
/// chats are refused in it.
final class AppMcpServerImpl implements IAppMcpServer {
  /// Creates the server; [start] begins listening.
  AppMcpServerImpl({
    required this._tokens,
    required List<AppMcpTool> tools,
    required this._instructions,
    AppMcpBind? bind,
  }) : _tools = List<AppMcpTool>.unmodifiable(tools),
       _bind = bind ?? _defaultBind;

  static const String _host = '127.0.0.1';
  static const String _path = '/mcp';

  final AppMcpTokens _tokens;
  final List<AppMcpTool> _tools;
  final String _instructions;
  final AppMcpBind _bind;

  /// The chat of each MCP session: null until the session's first request after `initialize`.
  final Map<String, AppMcpCaller?> _callers = <String, AppMcpCaller?>{};

  StreamableMcpServer? _http;
  Uri? _url;
  Object? _startError;

  static Future<void> _defaultBind(StreamableMcpServer server) => server.start();

  @override
  Uri? get url => _url;

  @override
  int get toolCount => _tools.length;

  @override
  Object? get startError => _startError;

  @override
  Future<void> start() async {
    if (_http != null) return;
    setMcpLogHandler(_log);
    final metadata = _ProtectedResourceMetadata();
    final http = StreamableMcpServer(
      serverFactory: _createSession,
      host: _host,
      port: 0,
      path: _path,
      // The analyzer sees the package's web stubs, where the request is `dynamic`.
      authenticationHandler: (request) => _authenticate(request as HttpRequest),
      // Without it the package answers a refused request with 403; with it, 401 and a bearer
      // challenge. No authorization server is advertised: tokens come from the app only.
      oauthProtectedResource: OAuthProtectedResourceOptions(
        metadata: metadata,
        serveRootMetadata: false,
      ),
      enableDnsRebindingProtection: true,
      // Chats are told apart by MCP session, so the sessionless 2026-07-28 protocol is refused.
      protocol: McpProtocol.legacy,
    );
    try {
      await _bind(http);
    } on Object catch (error, stackTrace) {
      _startError = error;
      l.w('App MCP | the server could not start: $error', stackTrace);
      return;
    }
    _startError = null;
    _http = http;
    _url = metadata.bound = Uri(scheme: 'http', host: _host, port: http.boundPort, path: _path);
  }

  @override
  Future<void> close() async {
    final http = _http;
    _http = null;
    _url = null;
    _callers.clear();
    await http?.stop();
  }

  Future<StreamableMcpAuthenticationResult> _authenticate(HttpRequest request) async {
    final token = _bearerToken(request.headers.value(HttpHeaders.authorizationHeader));
    final caller = token == null ? null : await _tokens.resolve(token);
    if (caller == null) return const StreamableMcpAuthenticationResult.unauthorized();
    final sessionId = request.headers.value('mcp-session-id');
    // An unknown session id is answered by the package (404).
    if (sessionId == null || !_callers.containsKey(sessionId)) {
      return const StreamableMcpAuthenticationResult.allow();
    }
    final owner = _callers[sessionId];
    if (owner == null) {
      _callers[sessionId] = caller;
    } else if (owner != caller) {
      return const StreamableMcpAuthenticationResult.unauthorized(
        errorDescription: 'The token belongs to another chat.',
      );
    }
    return const StreamableMcpAuthenticationResult.allow();
  }

  static final RegExp _bearer = RegExp(r'^Bearer\s+(\S+)\s*$', caseSensitive: false);

  static String? _bearerToken(String? header) =>
      header == null ? null : _bearer.firstMatch(header)?.group(1);

  McpServer _createSession(String sessionId) {
    // Sessionless requests (an empty id) never get a chat, so their tool calls are refused.
    if (sessionId.isNotEmpty) _callers[sessionId] = null;
    final server = McpServer(
      const Implementation(name: appMcpServerName, version: '1.0.0'),
      options: McpServerOptions(instructions: _instructions, protocol: McpProtocol.legacy),
    );
    for (final tool in _tools) {
      server.registerTool(
        tool.name,
        description: tool.description,
        inputSchema: JsonSchema.fromJson(Map<String, dynamic>.of(tool.inputSchema)) as JsonObject,
        callback: (arguments, extra) => _call(tool, arguments, extra),
      );
    }
    return server;
  }

  Future<CallToolResult> _call(
    AppMcpTool tool,
    Map<String, dynamic> arguments,
    RequestHandlerExtra extra,
  ) async {
    final caller = _callers[extra.sessionId];
    if (caller == null) return _error('This MCP session is not bound to a chat.');
    final AppMcpResult result;
    try {
      result = await tool.call(caller, arguments);
    } on Object catch (error, stackTrace) {
      l.w('App MCP | ${tool.name} failed: $error', stackTrace);
      return _error('${tool.name} failed: $error');
    }
    return switch (result) {
      AppMcpText(:final text) => CallToolResult(content: <Content>[TextContent(text: text)]),
      AppMcpImage(:final png, :final caption) => CallToolResult(
        content: <Content>[
          ImageContent(data: base64Encode(png), mimeType: 'image/png'),
          if (caption != null) TextContent(text: caption),
        ],
      ),
      AppMcpError(:final message) => _error(message),
    };
  }

  static CallToolResult _error(String message) =>
      CallToolResult(content: <Content>[TextContent(text: message)], isError: true);

  /// The package's own diagnostics. Only failures are kept: the rest is a line per HTTP request.
  /// They never carry a token.
  static void _log(String logger, LogLevel level, String message) {
    if (level == LogLevel.error || level == LogLevel.warn) l.w('MCP | $logger: $message');
  }
}

/// Protected-resource metadata whose resource is the server's URL once the port is known.
final class _ProtectedResourceMetadata extends OAuthProtectedResourceMetadata {
  _ProtectedResourceMetadata()
    : super(
        resource: Uri(scheme: 'http', host: '127.0.0.1', path: '/mcp'),
        authorizationServers: const <Uri>[],
      );

  Uri? bound;

  @override
  Uri get resource => bound ?? super.resource;
}
