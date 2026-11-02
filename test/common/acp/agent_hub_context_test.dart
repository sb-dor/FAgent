import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/agent_connection.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_context.dart';
import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_agent_binary.dart';

/// Completes when [notifier] reaches a value matching [test].
Future<void> _until<T>(ValueListenable<T> notifier, bool Function(T value) test) {
  if (test(notifier.value)) return Future<void>.value();
  final done = Completer<void>();
  void listener() {
    if (test(notifier.value) && !done.isCompleted) done.complete();
  }

  notifier.addListener(listener);
  return done.future
      .timeout(const Duration(seconds: 15))
      .whenComplete(() => notifier.removeListener(listener));
}

List<String> _agentText(LiveSession live) => <String>[
  for (final event in live.store.events)
    if (event.kind == 'agent_message_chunk')
      if (event.payload case {'params': {'update': {'content': {'text': final String text}}}}) text,
];

/// The content blocks of every prompt in the journal of [live], in order.
List<List<Map<String, Object?>>> _prompts(LiveSession live) => <List<Map<String, Object?>>>[
  for (final event in live.store.events)
    if (event.kind == SessionEventKind.prompt)
      <Map<String, Object?>>[
        for (final block in event.payload['prompt']! as List<Object?>)
          (block! as Map<Object?, Object?>).cast<String, Object?>(),
      ],
];

bool _isRules(Map<String, Object?> block) =>
    block['type'] == 'resource' &&
    (block['resource'] as Map<Object?, Object?>?)?['uri'] == rulesResourceUri;

void main() {
  late Directory temp;
  late AgentDefinition compiled;
  late ShellEnvironment environment;
  late AppDatabase database;
  late int projectId;
  late File requests;
  final hubs = <AgentHub>[];

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('agent_hub_context_test');
    compiled = await compileFakeAgent(temp);
    environment = await ShellEnvironment.resolve();
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  setUp(() async {
    requests = File('${temp.path}/requests-${DateTime.now().microsecondsSinceEpoch}.jsonl');
    database = AppDatabase(NativeDatabase.memory());
    projectId = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: temp.path, name: 'project'));
  });

  tearDown(() async {
    for (final hub in hubs) {
      await hub.dispose();
    }
    hubs.clear();
    await database.close();
  });

  AgentHub newHub({
    SessionContextProvider? sessionContext,
    RulesChannel rulesChannel = RulesChannel.firstMessage,
    Map<String, String> agentEnvironment = const <String, String>{},
  }) {
    final agent = AgentDefinition(
      id: 'fake',
      displayName: compiled.displayName,
      executable: compiled.executable,
      loginArguments: compiled.loginArguments,
      rulesChannel: rulesChannel,
      environment: <String, String>{'FAKE_AGENT_REQUESTS_FILE': requests.path, ...agentEnvironment},
    );
    final hub = AgentHub(
      database: database,
      environment: environment,
      agents: <String, AgentDefinition>{'fake': agent},
      sessionContext: sessionContext,
      connector: (definition, onPermission) => AgentConnection.start(
        definition: definition,
        environment: environment,
        onPermissionRequest: onPermission,
        initializeTimeout: const Duration(seconds: 20),
      ),
      cancelTimeout: const Duration(seconds: 1),
    );
    hubs.add(hub);
    return hub;
  }

  Future<void> restart() async {
    for (final hub in hubs) {
      await hub.dispose();
    }
    hubs.clear();
  }

  Future<int> newChat({String? acpSessionId}) => database
      .into(database.sessionsTable)
      .insert(
        SessionsTableCompanion.insert(
          projectId: projectId,
          agentId: 'fake',
          acpSessionId: acpSessionId == null
              ? const Value<String?>.absent()
              : Value<String?>(acpSessionId),
        ),
      );

  List<Map<String, Object?>> recorded() => !requests.existsSync()
      ? const <Map<String, Object?>>[]
      : <Map<String, Object?>>[
          for (final line in requests.readAsLinesSync())
            if (line.isNotEmpty) jsonDecode(line) as Map<String, Object?>,
        ];

  Future<SessionContext> rules(int _, AgentDefinition _, Map<String, Object?> _) async =>
      const SessionContext(servers: [], firstMessageRules: 'Rules text');

  /// A session that got the app's server (the provider puts it in `servers`).
  Future<SessionContext> withApp(int _, AgentDefinition _, Map<String, Object?> _) async =>
      const SessionContext(servers: [], withAppServer: true);

  group('context', () {
    test('the provider gets the agent and its initialize result', () async {
      final asked = <(String, Object?)>[];
      final hub = newHub(
        sessionContext: (sessionId, agent, initializeResult) async {
          asked.add((agent.id, initializeResult['agentCapabilities']));
          return SessionContext.empty;
        },
      );

      await hub.prompt(await newChat(), 'echo hi');

      expect(asked, hasLength(1));
      expect(asked.single.$1, 'fake');
      expect(asked.single.$2, containsPair('loadSession', true));
    });

    test('systemPrompt reaches session/new and session/load raw', () async {
      Future<SessionContext> context(int _, AgentDefinition _, Map<String, Object?> _) async =>
          const SessionContext(servers: [], systemPrompt: 'Rules text');
      const expected = <String, Object?>{
        'mode': 'append',
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': 'Rules text'},
        ],
      };
      final chat = await newChat();
      await newHub(
        sessionContext: context,
        rulesChannel: RulesChannel.systemPrompt,
      ).prompt(chat, 'echo one');
      await restart();

      final second = newHub(sessionContext: context, rulesChannel: RulesChannel.systemPrompt);
      await second.prompt(chat, 'echo two');

      final sent = recorded();
      expect(sent.map((r) => r['method']), <String>['session/new', 'session/load']);
      for (final request in sent) {
        final params = request['params']! as Map<String, Object?>;
        expect(params['systemPrompt'], expected);
        expect(params.containsKey('_meta'), isFalse);
      }
      final live = await second.session(chat);
      expect(_agentText(live).join(), 'onetwo');
      expect(_prompts(live).expand((p) => p).where(_isRules), isEmpty);
    });

    test('without systemPrompt the request has none', () async {
      await newHub(sessionContext: rules).prompt(await newChat(), 'echo hi');

      final params = recorded().single['params']! as Map<String, Object?>;
      expect(params.containsKey('systemPrompt'), isFalse);
    });

    test('rules resource only in the first prompt of a new session', () async {
      final hub = newHub(sessionContext: rules);
      final chat = await newChat();
      const file = <String, Object?>{
        'type': 'resource_link',
        'uri': 'file:///p/a.dart',
        'name': 'a.dart',
      };

      await hub.prompt(chat, 'echo one', resources: const [file]);
      await hub.prompt(chat, 'echo two');

      final live = await hub.session(chat);
      final prompts = _prompts(live);
      expect(prompts, hasLength(2));
      expect(prompts.first, hasLength(3));
      expect(prompts.first[0], <String, Object?>{'type': 'text', 'text': 'echo one'});
      expect(prompts.first[1], rulesResource('Rules text'));
      expect(prompts.first[2], containsPair('uri', 'file:///p/a.dart'));
      expect(prompts.last, <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': 'echo two'},
      ]);
      expect(_agentText(live).join(), 'onetwo');
    });

    test('no rules resource after session/load', () async {
      final chat = await newChat(acpSessionId: 'earlier');
      final hub = newHub(sessionContext: rules);

      await hub.prompt(chat, 'echo hi');

      expect(recorded().single['method'], 'session/load');
      final live = await hub.session(chat);
      expect(_prompts(live).single, <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': 'echo hi'},
      ]);
    });

    test('retry after a first-prompt failure sends text first', () async {
      final hub = newHub(sessionContext: rules);
      final chat = await newChat();
      final live = await hub.session(chat);
      await hub.prompt(chat, 'auth');
      expect(live.status.value, SessionStatus.needsAuth);
      await hub.authenticate('fake', 'browser-login');
      await _until(live.status, (s) => s == SessionStatus.cold);

      await hub.retryPrompt(chat);

      expect(_agentText(live), <String>['authenticated']);
      final prompts = _prompts(live);
      expect(prompts, hasLength(2));
      for (final prompt in prompts) {
        expect(prompt.first, <String, Object?>{'type': 'text', 'text': 'auth'});
        expect(prompt.where(_isRules), hasLength(1));
        expect(_isRules(prompt[1]), isTrue);
      }
    });

    test('rules on the first prompt after startNewAgentSession', () async {
      final hub = newHub(sessionContext: rules);
      final chat = await newChat(acpSessionId: 'missing');
      final live = await hub.session(chat);
      await expectLater(hub.prompt(chat, 'echo lost'), throwsA(anything));
      expect(live.status.value, SessionStatus.setupFailed);

      await hub.startNewAgentSession(chat);
      await hub.prompt(chat, 'echo fresh');

      expect(_prompts(live).single, <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': 'echo fresh'},
        rulesResource('Rules text'),
      ]);
    });

    test('rules exactly once across the bypass-consent retry', () async {
      final hub = newHub(
        sessionContext: rules,
        agentEnvironment: const <String, String>{
          'FAKE_AGENT_NEW_SESSION_MODE': 'bypassPermissions',
        },
      );
      final chat = await newChat();
      final live = await hub.session(chat);
      await expectLater(hub.prompt(chat, 'echo hi'), throwsA(isA<BypassNotAllowedException>()));
      expect(live.canRetryPrompt.value, isTrue);

      await hub.acknowledgeBypass(chat);
      await hub.retryPrompt(chat);

      expect(_agentText(live).join(), 'hi');
      expect(_prompts(live).single, <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': 'echo hi'},
        rulesResource('Rules text'),
      ]);
    });

    test('skipped servers are one notice per chat start', () async {
      final hub = newHub(
        sessionContext: (_, _, _) async =>
            const SessionContext(servers: [], skippedServers: <String>['remote', 'events']),
      );
      final notices = <HubNotice>[];
      final subscription = hub.notices.listen(notices.add);
      addTearDown(subscription.cancel);
      final chat = await newChat();

      await hub.prompt(chat, 'echo one');
      await hub.prompt(chat, 'echo two');
      await pumpEventQueue();

      expect(notices, hasLength(1));
      expect(notices.single.sessionId, chat);
      expect(notices.single.message, contains('remote, events'));
    });
  });

  group('permissions', () {
    test('app tool permission is auto-allowed for a non-Claude agent', () async {
      final hub = newHub(sessionContext: withApp);
      final chat = await newChat();
      final live = await hub.session(chat);
      final statuses = <SessionStatus>[];
      live.status.addListener(() => statuses.add(live.status.value));

      await hub.prompt(chat, 'mcp-call codex flutter_code_agent list_skills');

      expect(statuses, isNot(contains(SessionStatus.awaitingPermission)));
      expect(_agentText(live), <String>['allow']);
      final request = live.store.events.singleWhere(
        (e) => e.kind == SessionEventKind.permissionRequest,
      );
      expect(
        live.store.events
            .singleWhere((e) => e.kind == SessionEventKind.permissionResolution)
            .payload,
        allOf(
          containsPair('requestId', request.payload['requestId']),
          containsPair('outcome', 'selected'),
          containsPair('optionId', 'allow'),
        ),
      );
    });

    test('the same title asks in a session that did not get the app server', () async {
      final hub = newHub();
      final chat = await newChat();
      final live = await hub.session(chat);

      final turn = hub.prompt(chat, 'mcp-call codex flutter_code_agent list_skills');
      await _until(live.status, (s) => s == SessionStatus.awaitingPermission);
      final request = live.store.events.singleWhere(
        (e) => e.kind == SessionEventKind.permissionRequest,
      );
      expect(
        hub.resolvePermission(chat, request.payload['requestId']! as String, 'reject'),
        isTrue,
      );
      await turn;

      expect(_agentText(live), <String>['reject']);
    });

    test('other permissions still ask', () async {
      final hub = newHub(sessionContext: withApp);
      final chat = await newChat();
      final live = await hub.session(chat);

      final turn = hub.prompt(chat, 'permission');
      await _until(live.status, (s) => s == SessionStatus.awaitingPermission);
      final request = live.store.events.singleWhere(
        (e) => e.kind == SessionEventKind.permissionRequest,
      );
      expect(
        hub.resolvePermission(chat, request.payload['requestId']! as String, 'reject'),
        isTrue,
      );
      await turn;

      expect(_agentText(live), <String>['reject']);
    });

    test('a Gemini-style app tool permission is auto-allowed', () async {
      final hub = newHub(sessionContext: withApp);
      final chat = await newChat();
      final live = await hub.session(chat);

      await hub.prompt(chat, 'mcp-call gemini flutter_code_agent list_skills');

      expect(_agentText(live), <String>['allow']);
    });

    test('a Codex-style call of another server still asks', () async {
      final hub = newHub(sessionContext: withApp);
      final chat = await newChat();
      final live = await hub.session(chat);

      final turn = hub.prompt(chat, 'mcp-call codex other list_skills');
      await _until(live.status, (s) => s == SessionStatus.awaitingPermission);
      final request = live.store.events.singleWhere(
        (e) => e.kind == SessionEventKind.permissionRequest,
      );
      expect(
        hub.resolvePermission(chat, request.payload['requestId']! as String, 'reject'),
        isTrue,
      );
      await turn;

      expect(_agentText(live), <String>['reject']);
    });

    test('app tool permission still asks for Claude, which allows it with allowedTools', () async {
      final hub = newHub(sessionContext: withApp, rulesChannel: RulesChannel.claudeMeta);
      final chat = await newChat();
      final live = await hub.session(chat);

      final turn = hub.prompt(chat, 'mcp-call codex flutter_code_agent list_skills');
      await _until(live.status, (s) => s == SessionStatus.awaitingPermission);
      final request = live.store.events.singleWhere(
        (e) => e.kind == SessionEventKind.permissionRequest,
      );
      expect(hub.resolvePermission(chat, request.payload['requestId']! as String, 'allow'), isTrue);
      await turn;
    });
  });

  group('isAppToolPermission', () {
    Map<String, Object?> request(Map<String, Object?> toolCall) => <String, Object?>{
      'sessionId': 's',
      'toolCall': <String, Object?>{'toolCallId': 'c1', ...toolCall},
      'options': const <Object?>[],
    };

    // As codex-acp 2.5.0 sent them (opt-in run, workspace-write mode): the identity is only in
    // the announcing `tool_call` update; the permission request names just the call.
    const codexCallId = 'exec-53fb5580-7efe-4888-92b0-66f183e71513';
    final codexAnnounced = jsonDecode('''
      {"toolCallId": "$codexCallId", "kind": "execute",
       "title": "mcp.flutter_code_agent.list_skills", "status": "in_progress",
       "rawInput": {"server": "flutter_code_agent", "tool": "list_skills", "arguments": {}},
       "_meta": {"is_mcp_tool_call": true}}
    ''') as Map<String, Object?>;
    final codexRequest = jsonDecode('''
      {"sessionId": "01a19b73-b14d-75e2-8f94-f06f4b5bf422",
       "toolCall": {"toolCallId": "$codexCallId", "kind": "execute", "status": "pending"},
       "options": [{"optionId": "allow_once", "name": "Allow", "kind": "allow_once"},
                   {"optionId": "allow_session", "name": "Allow for this session",
                    "kind": "allow_always"},
                   {"optionId": "allow_always", "name": "Always allow", "kind": "allow_always"},
                   {"optionId": "cancel", "name": "Cancel", "kind": "reject_once"}]}
    ''') as Map<String, Object?>;
    // As Gemini CLI 0.66.0 builds it for an MCP tool called without arguments.
    final geminiRequest = jsonDecode('''
      {"sessionId": "s",
       "toolCall": {"toolCallId": "list_skills-1793609305463", "status": "pending",
                    "title": "list_skills (flutter_code_agent MCP Server)",
                    "content": [], "locations": [], "kind": "other"},
       "options": [{"optionId": "proceed_always_server",
                    "name": "Allow all server tools for this session", "kind": "allow_always"}]}
    ''') as Map<String, Object?>;

    Map<String, Object?> withField(Map<String, Object?> json, String key, Object? value) =>
        <String, Object?>{...json, key: value};

    test("Codex's request with its announced call", () {
      expect(isAppToolPermission(codexRequest, announced: codexAnnounced), isTrue);
    });

    test("Codex's request alone names no server", () {
      expect(isAppToolPermission(codexRequest), isFalse);
    });

    test('a Codex-style call needs the title, rawInput and the MCP marker to agree', () {
      for (final announced in <Map<String, Object?>>[
        // Another server, or a tool name with something after it.
        withField(codexAnnounced, 'title', 'mcp.other.list_skills'),
        withField(codexAnnounced, 'title', 'mcp.flutter_code_agent.list_skills --rm'),
        withField(codexAnnounced, 'title', 'mcp.my_flutter_code_agent.list_skills'),
        // A shell command named like the tool.
        withField(codexAnnounced, 'rawInput', <String, Object?>{
          'command': <String>['mcp.flutter_code_agent.list_skills'],
        }),
        withField(codexAnnounced, 'rawInput', <String, Object?>{
          'server': 'other',
          'tool': 'list_skills',
        }),
        withField(codexAnnounced, 'rawInput', <String, Object?>{
          'server': 'flutter_code_agent',
          'tool': 'rm',
        }),
        withField(codexAnnounced, '_meta', null),
        withField(codexAnnounced, '_meta', <String, Object?>{'is_mcp_tool_call': 'true'}),
      ]) {
        expect(
          isAppToolPermission(codexRequest, announced: announced),
          isFalse,
          reason: jsonEncode(announced),
        );
      }
    });

    test("the request's own fields win over the announced call", () {
      expect(
        isAppToolPermission(
          request({'toolCallId': codexCallId, 'kind': 'execute', 'title': 'rm -rf build'}),
          announced: codexAnnounced,
        ),
        isFalse,
      );
    });

    test("Gemini's request for a tool without arguments", () {
      expect(isAppToolPermission(geminiRequest), isTrue);
    });

    test('a Gemini-style title must name the app server as the whole suffix', () {
      for (final title in <String>[
        'flutter_code_agent.x (other MCP Server)',
        'x (other MCP Server)',
        'foo (flutter_code_agent MCP Server) (evil MCP Server)',
        'list_skills (my_flutter_code_agent MCP Server)',
        'rm -rf / (flutter_code_agent MCP Server)',
        // With arguments Gemini titles the call `tool(arg: value)` without the server.
        'load_skill(name: flutter-testing)',
      ]) {
        expect(
          isAppToolPermission(request({'title': title, 'kind': 'other'})),
          isFalse,
          reason: title,
        );
      }
      expect(
        isAppToolPermission(
          request({'title': 'list_skills (flutter_code_agent MCP Server)', 'kind': 'execute'}),
        ),
        isFalse,
      );
    });

    test('forms no agent sends do not count', () {
      for (final title in <String>[
        'flutter_code_agent',
        'flutter_code_agent.list_skills',
        'flutter_code_agent__list_skills',
        'flutter_code_agent:list_skills',
        'mcp__flutter_code_agent__list_skills',
        'Tool list_skills from flutter_code_agent MCP',
      ]) {
        expect(
          isAppToolPermission(request({'title': title, 'kind': 'other'})),
          isFalse,
          reason: title,
        );
      }
      // A server field without Codex's title and marker.
      expect(
        isAppToolPermission(
          request({
            'title': 'list_skills',
            'rawInput': {'server': 'flutter_code_agent', 'tool': 'list_skills'},
          }),
        ),
        isFalse,
      );
      expect(
        isAppToolPermission(
          request({
            'title': 'list_skills',
            '_meta': {'serverName': 'flutter_code_agent'},
          }),
        ),
        isFalse,
      );
    });

    test('argument values, contents and locations that mention the server are not', () {
      expect(
        isAppToolPermission(
          request({
            'title': 'search',
            'kind': 'other',
            'rawInput': {'query': 'flutter_code_agent', 'server': 'search'},
          }),
        ),
        isFalse,
      );
      expect(
        isAppToolPermission(
          request({'title': 'grep -r flutter_code_agent lib', 'kind': 'execute'}),
        ),
        isFalse,
      );
      expect(
        isAppToolPermission(
          request({
            'title': 'Edit lib/main.dart',
            'kind': 'edit',
            'content': [
              {
                'type': 'diff',
                'path': '/p/lib/main.dart',
                'newText': 'package:flutter_code_agent/',
              },
            ],
          }),
        ),
        isFalse,
      );
      expect(
        isAppToolPermission(
          request({
            'title': 'Read file',
            'kind': 'read',
            'locations': [
              {'path': '/Users/me/flutter_code_agent/lib/main.dart'},
            ],
          }),
        ),
        isFalse,
      );
      expect(isAppToolPermission(request({'title': 'dart (MCP Server)'})), isFalse);
      expect(isAppToolPermission(<String, Object?>{'sessionId': 's'}), isFalse);
    });
  });

  group('announcedToolCall', () {
    var seq = 0;
    SessionEvent frame(String kind, Map<String, Object?> update, {SessionEventOrigin? origin}) =>
        SessionEvent(
          seq: seq++,
          origin: origin ?? SessionEventOrigin.agent,
          kind: kind,
          payload: <String, Object?>{
            'jsonrpc': '2.0',
            'method': 'session/update',
            'params': <String, Object?>{
              'sessionId': 's',
              'update': <String, Object?>{'sessionUpdate': kind, ...update},
            },
          },
          createdAt: DateTime(2026),
        );

    test('merges the tool_call and its updates in order', () {
      final events = <SessionEvent>[
        frame('tool_call', {'toolCallId': 'a', 'title': 'one', 'kind': 'execute'}),
        frame('tool_call', {'toolCallId': 'b', 'title': 'other call'}),
        frame('tool_call_update', {'toolCallId': 'a', 'title': 'two', 'status': 'in_progress'}),
      ];

      expect(announcedToolCall(events, 'a'), <String, Object?>{
        'toolCallId': 'a',
        'title': 'two',
        'kind': 'execute',
        'status': 'in_progress',
      });
    });

    test('null without an agent frame of that call', () {
      expect(announcedToolCall(const <SessionEvent>[], 'a'), isNull);
      // A request without a call id matches no frame, not the frames without one.
      expect(
        announcedToolCall(<SessionEvent>[
          frame('tool_call', {'title': 'mcp.flutter_code_agent.list_skills'}),
        ], null),
        isNull,
      );
      expect(
        announcedToolCall(<SessionEvent>[
          frame('tool_call', {'toolCallId': 'a'}, origin: SessionEventOrigin.user),
          frame('tool_call', {'toolCallId': 'b'}),
        ], 'a'),
        isNull,
      );
    });
  });
}
