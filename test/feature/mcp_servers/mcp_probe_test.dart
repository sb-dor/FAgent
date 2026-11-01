import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tokens.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tool.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_probe.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart' show setMcpLogHandler;
import 'package:path/path.dart' as p;

import '../../support/scripted_mcp_server_binary.dart';

/// Whether any process of the group [pgid] is alive (`kill -0` on the group).
bool _groupAlive(int pgid) => Process.runSync('kill', <String>['-0', '--', '-$pgid']).exitCode == 0;

bool _alive(int pid) => Process.runSync('kill', <String>['-0', '$pid']).exitCode == 0;

final class _NoTool implements AppMcpTool {
  @override
  String get name => 'noop';

  @override
  String get description => 'Does nothing.';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{'type': 'object'};

  @override
  Future<AppMcpResult> call(AppMcpCaller caller, Map<String, Object?> arguments) async =>
      const AppMcpText('ok');
}

void main() {
  late Directory temp;
  late String scripted;
  late McpProbeImpl probe;

  setUpAll(() async {
    // The client package prints every handshake; the probe reports what matters itself.
    setMcpLogHandler((logger, level, message) {});
    temp = Directory.systemTemp.createTempSync('mcp_probe_test');
    scripted = await compileScriptedMcpServer(temp);
  });
  tearDownAll(() => temp.deleteSync(recursive: true));

  setUp(() {
    probe = McpProbeImpl(
      environment: const ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'}),
    );
  });

  McpServer stdio(List<String> args, {String? command, Map<String, String> env = const {}}) =>
      McpServer(
        id: 'user:1',
        name: 'scripted',
        transport: McpTransport.stdio,
        command: command ?? scripted,
        args: args,
        env: env,
      );

  group('stdio', () {
    test('counts the tools of a server that answers initialize and tools/list', () async {
      final result = await probe.probe(stdio(['tools', '3']));

      expect(result, const McpProbeConnected(3));
    });

    test('a server without tools is connected with 0', () async {
      expect(await probe.probe(stdio(['tools', '0'])), const McpProbeConnected(0));
    });

    test('a server that never answers times out and its whole group is killed', () async {
      final pidFile = p.join(temp.path, 'silent.pid');
      final started = DateTime.now();

      final result = await probe.probe(
        stdio(['silent', pidFile]),
        timeout: const Duration(seconds: 2),
      );

      expect(result, const McpProbeFailed('Timed out'));
      expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 8)));
      final pid = int.parse(File(pidFile).readAsStringSync());
      final child = int.parse(File('$pidFile.child').readAsStringSync());
      expect(_groupAlive(pid), isFalse, reason: 'the process group $pid is gone');
      expect(_alive(child), isFalse, reason: 'the sleep started by the server is gone');
    });

    test('the group is gone after a successful probe too', () async {
      // The server exits on EOF, but the `sleep` it started would outlive it without the kill.
      final pidFile = p.join(temp.path, 'tools.pid');

      final result = await probe.probe(stdio(['tools', '1', pidFile]));

      expect(result, const McpProbeConnected(1));
      final pid = int.parse(File(pidFile).readAsStringSync());
      final child = int.parse(File('$pidFile.child').readAsStringSync());
      expect(_groupAlive(pid), isFalse, reason: 'the process group $pid is gone');
      expect(_alive(child), isFalse, reason: 'the sleep started by the server is gone');
    });

    test('dispose kills the group of a probe that is in flight and fails it', () async {
      final pidFile = p.join(temp.path, 'disposed.pid');
      final running = probe.probe(stdio(['silent', pidFile]), timeout: const Duration(seconds: 60));
      while (!File(pidFile).existsSync() || File(pidFile).readAsStringSync().isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final pid = int.parse(File(pidFile).readAsStringSync());
      final child = int.parse(File('$pidFile.child').readAsStringSync());
      expect(_groupAlive(pid), isTrue);

      await probe.dispose();

      expect(_groupAlive(pid), isFalse, reason: 'the process group $pid is gone');
      expect(_alive(child), isFalse, reason: 'the sleep started by the server is gone');
      expect(await running.timeout(const Duration(seconds: 5)), isA<McpProbeFailed>());
    });

    test('dispose waits for several probes and kills them all', () async {
      final files = [for (var i = 0; i < 2; i++) p.join(temp.path, 'many$i.pid')];
      final running = [
        for (final file in files)
          probe.probe(stdio(['silent', file]), timeout: const Duration(seconds: 60)),
      ];
      for (final file in files) {
        while (!File(file).existsSync() || File(file).readAsStringSync().isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      await probe.dispose();

      for (final file in files) {
        expect(_groupAlive(int.parse(File(file).readAsStringSync())), isFalse);
      }
      for (final result in await Future.wait(running)) {
        expect(result, isA<McpProbeFailed>());
      }
    });

    test('a probe after dispose fails at once without starting anything', () async {
      final pidFile = p.join(temp.path, 'late.pid');
      await probe.dispose();

      final result = await probe.probe(stdio(['silent', pidFile]));

      expect(result, const McpProbeFailed('Stopped'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(File(pidFile).existsSync(), isFalse);
    });

    test('a command that does not exist fails with a message', () async {
      final result = await probe.probe(stdio(const [], command: '/no/such/mcp-server'));

      expect(result, isA<McpProbeFailed>());
      expect((result as McpProbeFailed).message, isNotEmpty);
    });

    test('a server that exits reports what it wrote to stderr', () async {
      final result = await probe.probe(stdio(['stderr', 'boom: bad config']));

      expect(result, isA<McpProbeFailed>());
      expect((result as McpProbeFailed).message, contains('boom: bad config'));
    });

    test('a stdio server without a command fails', () async {
      final result = await probe.probe(
        const McpServer(id: 'user:2', name: 'x', transport: McpTransport.stdio),
      );

      expect(result, const McpProbeFailed('No command'));
    });

    test('the server gets the login shell environment plus its own', () async {
      final result = await probe.probe(stdio(['env', 'PATH', 'A'], env: {'A': 'b'}));

      expect(result, isA<McpProbeFailed>());
      expect((result as McpProbeFailed).message, contains('PATH=/usr/bin:/bin A=b'));
    });
  });

  group('http', () {
    late AppDatabase database;
    late AppMcpTokens tokens;
    late AppMcpServerImpl server;
    late String token;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      final project = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/tmp/demo', name: 'demo'));
      final chat = await database
          .into(database.sessionsTable)
          .insert(SessionsTableCompanion.insert(projectId: project, agentId: 'claude'));
      tokens = AppMcpTokens(database: database);
      token = tokens.issue(chat, project);
      server = AppMcpServerImpl(
        tokens: tokens,
        tools: <AppMcpTool>[_NoTool()],
        instructions: appMcpInstructions,
      );
      await server.start();
    });

    tearDown(() async {
      await server.close();
      await database.close();
    });

    McpServer http({Map<String, String> headers = const {}, String? url}) => McpServer(
      id: 'user:3',
      name: 'remote',
      transport: McpTransport.http,
      url: url ?? '${server.url}',
      headers: headers,
    );

    test('a 401 means the server needs a sign-in', () async {
      expect(await probe.probe(http()), const McpProbeNeedsAuth());
    });

    test('the configured headers are sent', () async {
      final result = await probe.probe(http(headers: {'Authorization': 'Bearer $token'}));

      expect(result, const McpProbeConnected(1));
    });

    test('a refused connection fails with a message', () async {
      final result = await probe.probe(http(url: 'http://127.0.0.1:1/mcp'));

      expect(result, isA<McpProbeFailed>());
    });

    test('an http server without a URL fails', () async {
      final result = await probe.probe(
        const McpServer(id: 'user:4', name: 'x', transport: McpTransport.http),
      );

      expect(result, const McpProbeFailed('No URL'));
    });

    test('a server that does not answer times out', () async {
      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(silent.close);
      silent.listen((socket) => socket.listen((_) {}));

      final result = await probe.probe(
        http(url: 'http://127.0.0.1:${silent.port}/mcp'),
        timeout: const Duration(seconds: 1),
      );

      expect(result, const McpProbeFailed('Timed out'));
    });
  });
}
