import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tokens.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tool.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Records every call and answers with [result].
final class _FakeTool implements AppMcpTool {
  _FakeTool(this.name, this.result);

  @override
  final String name;

  final AppMcpResult result;

  final List<(AppMcpCaller, Map<String, Object?>)> calls = <(AppMcpCaller, Map<String, Object?>)>[];

  @override
  String get description => 'The $name test tool.';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'text': <String, Object?>{'type': 'string'},
    },
  };

  @override
  Future<AppMcpResult> call(AppMcpCaller caller, Map<String, Object?> arguments) async {
    calls.add((caller, arguments));
    return result;
  }
}

/// Initializes a session like Claude Code does; the server refuses the sessionless protocol.
const _clientOptions = McpClientOptions(protocol: McpProtocol.legacy);

const _png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];

void main() {
  late AppDatabase database;
  late AppMcpTokens tokens;
  late _FakeTool echo;
  late AppMcpServerImpl server;
  late int projectId;
  late int chatA;
  late int chatB;
  final clients = <McpClient>[];

  Future<int> insertChat() => database
      .into(database.sessionsTable)
      .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: 'claude'));

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    projectId = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: '/tmp/demo', name: 'demo'));
    chatA = await insertChat();
    chatB = await insertChat();
    tokens = AppMcpTokens(database: database);
    echo = _FakeTool('echo', const AppMcpText('echoed'));
    server = AppMcpServerImpl(
      tokens: tokens,
      tools: <AppMcpTool>[
        echo,
        _FakeTool('fail', const AppMcpError('Nothing is running.')),
        _FakeTool('shot', const AppMcpImage(_png, caption: 'Saved to /tmp/shot.png')),
      ],
      instructions: appMcpInstructions,
    );
    await server.start();
  });

  tearDown(() async {
    for (final client in clients) {
      await client.close();
    }
    clients.clear();
    await server.close();
    await database.close();
  });

  /// An MCP client connected with [token].
  Future<(McpClient, StreamableHttpClientTransport)> connect(String token) async {
    final transport = StreamableHttpClientTransport(
      server.url!,
      opts: StreamableHttpClientTransportOptions(
        requestInit: <String, dynamic>{
          'headers': <String, dynamic>{'Authorization': 'Bearer $token'},
        },
      ),
    );
    final client = McpClient(
      const Implementation(name: 'test', version: '1.0.0'),
      options: _clientOptions,
    );
    clients.add(client);
    await client.connect(transport);
    return (client, transport);
  }

  /// The HTTP status of a raw POST of `initialize` (or `ping` within [sessionId]).
  Future<int> post({String? token, String? host, String? sessionId}) async {
    final http = HttpClient();
    try {
      final request = await http.postUrl(server.url!);
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream');
      if (token != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (host != null) request.headers.host = host;
      if (sessionId != null) request.headers.set('mcp-session-id', sessionId);
      request.write(
        jsonEncode(
          sessionId != null
              ? <String, Object?>{'jsonrpc': '2.0', 'id': 7, 'method': 'ping'}
              : <String, Object?>{
                  'jsonrpc': '2.0',
                  'id': 1,
                  'method': 'initialize',
                  'params': <String, Object?>{
                    'protocolVersion': '2025-06-18',
                    'capabilities': <String, Object?>{},
                    'clientInfo': <String, Object?>{'name': 'raw', 'version': '1.0.0'},
                  },
                },
        ),
      );
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      http.close(force: true);
    }
  }

  group('AppMcpServerImpl', () {
    test('listens on 127.0.0.1 at /mcp with the registered tools', () {
      expect(server.startError, isNull);
      expect(server.url, isNotNull);
      expect(server.url!.host, '127.0.0.1');
      expect(server.url!.port, isNonZero);
      expect(server.url!.path, '/mcp');
      expect(server.toolCount, 3);
    });

    test('rejects a request without a token with 401', () async {
      expect(await post(), HttpStatus.unauthorized);
    });

    test('the MCP client sees a missing token as unauthorized', () async {
      final client = McpClient(
        const Implementation(name: 'test', version: '1.0.0'),
        options: _clientOptions,
      );
      clients.add(client);
      await expectLater(
        client.connect(StreamableHttpClientTransport(server.url!)),
        throwsA(isA<McpError>().having((error) => error.message, 'message', contains('401'))),
      );
    });

    test('rejects an unknown token with 401', () async {
      tokens.issue(chatA, projectId);
      expect(await post(token: 'not-a-token'), HttpStatus.unauthorized);
    });

    test('rejects a replaced token with 401', () async {
      final old = tokens.issue(chatA, projectId);
      tokens.issue(chatA, projectId);
      expect(await post(token: old), HttpStatus.unauthorized);
    });

    test('rejects the token of a deleted chat with 401', () async {
      final token = tokens.issue(chatA, projectId);
      expect(await post(token: token), HttpStatus.ok);

      await (database.delete(database.sessionsTable)..where((s) => s.id.equals(chatA))).go();

      expect(await post(token: token), HttpStatus.unauthorized);
    });

    test('rejects a foreign Host header (DNS rebinding)', () async {
      final token = tokens.issue(chatA, projectId);
      expect(await post(token: token, host: 'evil.example'), HttpStatus.forbidden);
    });

    test('lists the registered tools to a valid token', () async {
      final (client, _) = await connect(tokens.issue(chatA, projectId));

      final tools = (await client.listTools()).tools;

      expect(tools.map((tool) => tool.name), <String>['echo', 'fail', 'shot']);
      expect(tools.first.description, 'The echo test tool.');
      expect(client.getServerVersion()?.name, appMcpServerName);
      expect(client.getInstructions(), appMcpInstructions);
    });

    test('a tool call gets the chat of the token and the arguments', () async {
      final (clientA, _) = await connect(tokens.issue(chatA, projectId));
      final (clientB, _) = await connect(tokens.issue(chatB, projectId));

      final result = await clientA.callTool(
        const CallToolRequest(name: 'echo', arguments: <String, dynamic>{'text': 'hi'}),
      );
      await clientB.callTool(const CallToolRequest(name: 'echo', arguments: <String, dynamic>{}));

      expect(result.isError, isFalse);
      expect((result.content.single as TextContent).text, 'echoed');
      expect(echo.calls.map((call) => call.$1), <AppMcpCaller>[
        (sessionId: chatA, projectId: projectId),
        (sessionId: chatB, projectId: projectId),
      ]);
      expect(echo.calls.first.$2, <String, Object?>{'text': 'hi'});
    });

    test('an AppMcpError arrives as isError with its message', () async {
      final (client, _) = await connect(tokens.issue(chatA, projectId));

      final result = await client.callTool(
        const CallToolRequest(name: 'fail', arguments: <String, dynamic>{}),
      );

      expect(result.isError, isTrue);
      expect((result.content.single as TextContent).text, 'Nothing is running.');
    });

    test('an AppMcpImage arrives as image/png content with its caption', () async {
      final (client, _) = await connect(tokens.issue(chatA, projectId));

      final result = await client.callTool(
        const CallToolRequest(name: 'shot', arguments: <String, dynamic>{}),
      );

      expect(result.isError, isFalse);
      final image = result.content.first as ImageContent;
      expect(image.mimeType, 'image/png');
      expect(base64Decode(image.data), _png);
      expect((result.content.last as TextContent).text, 'Saved to /tmp/shot.png');
    });

    test('a token of another chat cannot use an MCP session', () async {
      final (_, transport) = await connect(tokens.issue(chatA, projectId));
      final tokenB = tokens.issue(chatB, projectId);

      expect(await post(token: tokenB, sessionId: transport.sessionId), HttpStatus.unauthorized);
    });

    test('a valid MCP session does not let through the token of a deleted chat', () async {
      final tokenA = tokens.issue(chatA, projectId);
      final (client, transport) = await connect(tokenA);
      await client.listTools();

      await (database.delete(database.sessionsTable)..where((s) => s.id.equals(chatA))).go();

      expect(await post(token: tokenA, sessionId: transport.sessionId), HttpStatus.unauthorized);
      expect(echo.calls, isEmpty);
    });

    test('close stops listening', () async {
      final url = server.url!;
      await server.close();

      expect(server.url, isNull);
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      await expectLater(http.postUrl(url).then((request) => request.close()), throwsA(anything));
    });

    test('a failed bind leaves the server off without throwing', () async {
      final failing = AppMcpServerImpl(
        tokens: tokens,
        tools: <AppMcpTool>[echo],
        instructions: appMcpInstructions,
        bind: (_) async => throw const SocketException('Address already in use'),
      );

      await failing.start();

      expect(failing.startError, isA<SocketException>());
      expect(failing.url, isNull);
      await failing.close();
    });
  });

  group('AppMcpTokens', () {
    test('a token is 32 random bytes in base64url', () {
      final first = tokens.issue(chatA, projectId);
      final second = tokens.issue(chatB, projectId);

      expect(base64Url.decode(first), hasLength(32));
      expect(first, isNot(second));
    });

    test('resolve returns the chat of a live token', () async {
      final token = tokens.issue(chatA, projectId);

      expect(await tokens.resolve(token), (sessionId: chatA, projectId: projectId));
    });
  });

  group('appMcpInstructions', () {
    test('fits the 2048 characters Claude Code keeps', () {
      expect(appMcpInstructions.length, lessThan(2048));
    });

    test('points the agent at skills, the DTD URI and hot reload', () {
      for (final name in <String>['list_skills', 'load_skill', 'app_status', 'dtd', 'hot_reload']) {
        expect(appMcpInstructions, contains(name));
      }
    });
  });
}
