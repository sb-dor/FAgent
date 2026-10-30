// Contract test against the pinned Claude ACP adapter (AgentDefinition.claude).
//
// Skipped by default (see dart_test.yaml). It spends a few small Claude turns.
//   flutter test --tags adapter --run-skipped test/contract/
// With RECORD_ACP_FIXTURES=1 it also rewrites test/fixtures/acp/*.ndjson, which
// the transcript tests replay. Each fixture line is a journal entry:
//   {"origin": "user" | "agent", "payload": <raw JSON>}
@Tags(<String>['adapter'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_acp_sdk/dart_acp_sdk.dart';
import 'package:flutter_code_agent/src/common/acp/agent_connection.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/raw_acp_message.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final bool _record = Platform.environment['RECORD_ACP_FIXTURES'] == '1';

final class _Journal {
  final List<Map<String, Object?>> entries = <Map<String, Object?>>[];

  void user(PromptRequest request) => entries.add(<String, Object?>{
    'origin': 'user',
    'payload': <String, Object?>{'method': 'session/prompt', 'params': request.toJson()},
  });

  void agent(RawAcpMessage message) =>
      entries.add(<String, Object?>{'origin': 'agent', 'payload': _sanitize(message.json)});

  // available_commands_update lists the recording user's installed skills and
  // commands (~38 KB): replace it so no personal setup lands in the repo.
  static Map<String, Object?> _sanitize(Map<String, Object?> json) {
    final params = json['params'];
    if (params is! Map || params['update'] is! Map) return json;
    final update = params['update'] as Map;
    if (update['sessionUpdate'] != 'available_commands_update') return json;
    return <String, Object?>{
      ...json,
      'params': <String, Object?>{
        ...params.cast<String, Object?>(),
        'update': <String, Object?>{
          ...update.cast<String, Object?>(),
          'availableCommands': <Object?>[
            <String, Object?>{
              'name': 'init',
              'description': 'Initialize a CLAUDE.md file',
              'input': null,
            },
            <String, Object?>{
              'name': 'review',
              'description': 'Review the current changes',
              'input': null,
            },
          ],
        },
      },
    };
  }

  void save(String name) {
    if (!_record) return;
    File(p.join('test', 'fixtures', 'acp', '$name.ndjson'))
      ..createSync(recursive: true)
      ..writeAsStringSync('${entries.map(jsonEncode).join('\n')}\n');
  }
}

void main() {
  late Directory project;
  late ShellEnvironment environment;
  final permissionRequests = <RequestPermissionRequest>[];

  setUpAll(() async {
    project = Directory.systemTemp.createTempSync('claude_contract');
    environment = await ShellEnvironment.resolve();
  });

  tearDownAll(() => project.deleteSync(recursive: true));

  Future<AgentConnection> start() => AgentConnection.start(
    definition: AgentDefinition.claude,
    environment: environment,
    onPermissionRequest: (context) async {
      permissionRequests.add(context.params);
      final allow = context.params.options.firstWhere(
        (o) => o.kind == PermissionOptionKind.allowOnce,
      );
      return RequestPermissionResponse(
        outcome: RequestPermissionOutcomeSelected(
          SelectedPermissionOutcome(optionId: allow.optionId),
        ),
      );
    },
  );

  Future<(String, Map<String, Object?>)> newSession(AgentConnection connection) async {
    final responses = <RawAcpMessage>[];
    final sub = connection.incoming.where((m) => m.isResponse).listen(responses.add);
    final response = await connection.agent.createSession(
      NewSessionRequest(cwd: project.path, mcpServers: const <McpServer>[]),
    );
    await sub.cancel();
    final raw = responses.lastWhere((m) => m.result?['sessionId'] == response.sessionId.value);
    return (response.sessionId.value, raw.result!);
  }

  Future<List<RawAcpMessage>> turn(
    AgentConnection connection,
    String sessionId,
    String text,
    _Journal journal,
  ) async {
    final messages = <RawAcpMessage>[];
    final sub = connection.incoming.where((m) => m.sessionId == sessionId).listen((m) {
      messages.add(m);
      journal.agent(m);
    });
    final request = PromptRequest(
      sessionId: SessionId(sessionId),
      prompt: <ContentBlock>[ContentBlockText(TextContent(text: text))],
    );
    journal.user(request);
    await connection.agent.sendPrompt(request);
    await sub.cancel();
    return messages;
  }

  String updateKind(RawAcpMessage m) => '${(m.params?['update'] as Map?)?['sessionUpdate']}';

  test('initialize advertises loadSession and terminal login methods', () async {
    final connection = await start();
    addTearDown(connection.close);
    final result = connection.initializeResult;

    expect((result['agentCapabilities']! as Map)['loadSession'], isTrue);
    final methods = (result['authMethods']! as List).cast<Map<Object?, Object?>>();
    expect(methods.map((m) => m['id']), containsAll(<String>['claude-ai-login', 'console-login']));
  });

  test('session/new exposes permission modes and config options', () async {
    final connection = await start();
    addTearDown(connection.close);
    final (_, result) = await newSession(connection);

    final modes = (result['modes']! as Map)['availableModes'] as List;
    expect(
      modes.map((m) => (m as Map)['id']),
      containsAll(<String>['default', 'acceptEdits', 'plan']),
    );
    expect(result['configOptions'], isA<List<Object?>>());
    if (_record) {
      File(p.join('test', 'fixtures', 'acp', 'new_session_result.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    }
  });

  test('a simple turn streams agent message chunks', () async {
    final connection = await start();
    addTearDown(connection.close);
    final (sessionId, _) = await newSession(connection);
    final journal = _Journal();

    final messages = await turn(
      connection,
      sessionId,
      'Reply with exactly the word pong and nothing else. Do not use tools.',
      journal,
    );

    final text = messages
        .where((m) => updateKind(m) == 'agent_message_chunk')
        .map((m) => ((m.params!['update']! as Map)['content']! as Map)['text'])
        .join();
    expect(text.toLowerCase(), contains('pong'));
    journal.save('simple_turn');
  });

  test('an edit asks for permission and reports a diff', () async {
    permissionRequests.clear();
    final connection = await start();
    addTearDown(connection.close);
    final (sessionId, _) = await newSession(connection);
    final journal = _Journal();

    final messages = await turn(
      connection,
      sessionId,
      'Create a file named hello.txt in the current directory containing exactly: hi. '
      'Use the Write tool. Do not run shell commands.',
      journal,
    );

    expect(File(p.join(project.path, 'hello.txt')).existsSync(), isTrue);
    expect(permissionRequests, isNotEmpty);
    final diffs = <Object?>[
      for (final m in messages)
        if (updateKind(m) case 'tool_call' || 'tool_call_update')
          for (final c in ((m.params!['update']! as Map)['content'] as List?) ?? const <Object?>[])
            if ((c as Map)['type'] == 'diff') c,
    ];
    expect(diffs, isNotEmpty, reason: 'edits should be reported as diff content');
    journal.save('edit_file');
  });

  test('session/load of an unknown session fails with a JSON-RPC error', () async {
    final connection = await start();
    addTearDown(connection.close);

    Object? error;
    try {
      await connection.agent.loadSession(
        LoadSessionRequest(
          sessionId: SessionId('00000000-0000-0000-0000-000000000000'),
          cwd: project.path,
          mcpServers: const <McpServer>[],
        ),
      );
    } on JsonRpcRequestException catch (e) {
      error = e;
      // Recorded for docs/M1_PLAN.md: which code means "not found".
      // ignore: avoid_print
      print('session/load unknown → code ${e.error.code}: ${e.error.message}');
    }
    expect(error, isNotNull);
  });

  test('session/load in a new process replays the history', () async {
    final first = await start();
    final (sessionId, _) = await newSession(first);
    await turn(first, sessionId, 'Remember the number 42. Reply with ok.', _Journal());
    await first.close();

    final second = await start();
    addTearDown(second.close);
    final replay = <RawAcpMessage>[];
    final sub = second.incoming.where((m) => m.sessionId == sessionId).listen(replay.add);
    await second.agent.loadSession(
      LoadSessionRequest(
        sessionId: SessionId(sessionId),
        cwd: project.path,
        mcpServers: const <McpServer>[],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sub.cancel();

    expect(replay.map(updateKind), contains('user_message_chunk'));
  });
}
