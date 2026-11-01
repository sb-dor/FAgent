// Opt-in: the real Claude ACP adapter talks to the real app MCP server.
//
//   FLUTTER_AGENT_TEST=1 flutter test test/integration/agent_knowledge_test.dart
//
// Needs network, Node.js 22+ and a logged-in Claude Code; it spends a few small Claude turns.
@Tags(<String>['agent'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tokens.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/app_mcp_tools/data/skill_tools.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/fake_flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_servers_repository.dart';
import 'package:flutter_code_agent/src/feature/session_context/data/session_context_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/builtin_knowledge.dart';
import 'package:flutter_code_agent/src/feature/skills/data/chat_skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skills_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/scripted_mcp_probe.dart';

/// The files of `assets/knowledge/` read from disk, keyed like the asset bundle does.
final class _DiskKnowledge implements IBuiltinKnowledge {
  @override
  Future<Map<String, String>> load() async {
    final root = Directory('assets/knowledge');
    return {
      for (final file in root.listSync(recursive: true).whereType<File>())
        p.posix.joinAll(p.split(p.relative(file.path, from: root.path))): file.readAsStringSync(),
    };
  }
}

const String _prompt =
    'Call the list_skills tool of flutter_code_agent and reply with the first skill name.';

void main() {
  final enabled = Platform.environment['FLUTTER_AGENT_TEST'] == '1';

  late Directory temp;
  late AppDatabase database;
  late AppMcpTokens tokens;
  late AppMcpServerImpl server;
  late AgentHub hub;
  late int projectId;
  late List<String> builtinSkills;

  setUpAll(() async {
    if (!enabled) return;
    temp = Directory.systemTemp.createTempSync('agent_knowledge');
    final project = Directory(p.join(temp.path, 'project'))..createSync();
    final environment = await ShellEnvironment.resolve();
    database = AppDatabase(NativeDatabase.memory());
    projectId = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: project.path, name: 'project'));
    final skills = SkillsRepositoryImpl(
      database: database,
      builtin: _DiskKnowledge(),
      userRoot: p.join(temp.path, 'support'),
    );
    builtinSkills = [
      for (final directory in Directory('assets/knowledge/skills').listSync())
        if (directory is Directory) p.basename(directory.path),
    ];
    final chatSkills = ChatSkillsRepositoryImpl(database: database);
    final catalog = ChatSkillCatalog(skills: skills, chatSkills: chatSkills);
    tokens = AppMcpTokens(database: database);
    server = AppMcpServerImpl(
      tokens: tokens,
      tools: [
        ListSkillsTool(catalog: catalog),
        LoadSkillTool(catalog: catalog, skills: skills),
        ReadSkillFileTool(catalog: catalog, builtin: _DiskKnowledge()),
      ],
      instructions: appMcpInstructions,
    );
    await server.start();
    final context = SessionContextRepositoryImpl(
      database: database,
      appServer: server,
      tokens: tokens,
      skills: skills,
      chatSkills: chatSkills,
      mcpServers: McpServersRepositoryImpl(
        database: database,
        appServer: server,
        probe: ScriptedMcpProbe(),
        flutterSdk: FakeFlutterSdkRepositoryImpl(which: (_) => null, step: Duration.zero),
      ),
      environment: environment,
    );
    hub = AgentHub(
      database: database,
      environment: environment,
      setupTimeout: const Duration(minutes: 3),
      sessionContext: (sessionId, agent) => context.forSession(sessionId: sessionId, agent: agent),
    );
  });

  tearDownAll(() async {
    if (!enabled) return;
    await hub.dispose();
    await server.close();
    await database.close();
    temp.deleteSync(recursive: true);
  });

  Future<int> newChat() => database
      .into(database.sessionsTable)
      .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: 'claude'));

  /// Sends [text] and returns the events of that turn. A permission request fails the test at
  /// once (the turn is stopped, since nobody would answer it).
  Future<List<SessionEvent>> turn(int chat, String text) async {
    final live = await hub.session(chat);
    final before = live.store.events.length;
    var asked = false;
    final watch = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (asked) return;
      if (live.store.events.skip(before).any((e) => e.kind == SessionEventKind.permissionRequest)) {
        asked = true;
        unawaited(hub.cancel(chat));
      }
    });
    try {
      await hub.prompt(chat, text).timeout(const Duration(minutes: 4));
    } finally {
      watch.cancel();
    }
    final events = live.store.events.skip(before).toList();
    expect(
      events.where((e) => e.kind == SessionEventKind.permissionRequest).map((e) => e.payload),
      isEmpty,
      reason: 'the app tools must not ask for permission',
    );
    return events;
  }

  String reply(List<SessionEvent> events) => [
    for (final event in events)
      if (event.kind == 'agent_message_chunk')
        if (event.payload case {'params': {'update': {'content': {'text': final String text}}}})
          text,
  ].join();

  /// The `tool_call` / `tool_call_update` events of [tool] of the app server.
  List<Map<String, Object?>> toolEvents(List<SessionEvent> events, String tool) => [
    for (final event in events)
      if (event.kind == 'tool_call' || event.kind == 'tool_call_update')
        if (jsonEncode(event.payload).contains('mcp__${appMcpServerName}__$tool')) event.payload,
  ];

  bool completed(List<Map<String, Object?>> calls) => calls.any(
    (payload) => switch (payload) {
      {'params': {'update': {'status': 'completed'}}} => true,
      _ => false,
    },
  );

  test(
    'Claude calls list_skills without asking and names a built-in skill',
    () async {
      final chat = await newChat();

      final events = await turn(chat, _prompt);

      final calls = toolEvents(events, 'list_skills');
      expect(calls, isNotEmpty, reason: 'list_skills was not called: ${reply(events)}');
      // The server only speaks the legacy protocol: a completed call means the tools were listed.
      expect(completed(calls), isTrue, reason: '$calls');
      expect(builtinSkills.any(reply(events).contains), isTrue, reason: reply(events));
    },
    skip: enabled ? false : 'Talks to the real Claude adapter; set FLUTTER_AGENT_TEST=1',
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'after a refused token a new session with a new token still gets the tools',
    () async {
      final stale = await newChat();
      await turn(stale, _prompt);
      // Replace the chat's token: the agent session keeps sending the old one and gets 401.
      tokens.issue(stale, projectId);
      final refused = await turn(stale, '$_prompt If the tool fails, say FAILED.');
      final refusedLive = await hub.session(stale);
      printOnFailure('after 401: ${reply(refused)} (${refusedLive.status.value})');

      final fresh = await newChat();
      final events = await turn(fresh, _prompt);

      final calls = toolEvents(events, 'list_skills');
      expect(calls, isNotEmpty, reason: 'list_skills was not called: ${reply(events)}');
      expect(completed(calls), isTrue, reason: '$calls');
      expect(builtinSkills.any(reply(events).contains), isTrue, reason: reply(events));
      expect(
        events.where(
          (e) => jsonEncode(e.payload).contains('mcp__${appMcpServerName}__authenticate'),
        ),
        isEmpty,
        reason: 'no OAuth sign-in for the app server',
      );
    },
    skip: enabled ? false : 'Talks to the real Claude adapter; set FLUTTER_AGENT_TEST=1',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
