// Opt-in: the real Codex and Gemini CLI ACP agents.
//
//   FLUTTER_AGENT_TEST=1 flutter test --tags agent test/integration/agents_test.dart
//
// Needs network, Node.js 22+ and a signed-in Codex (ChatGPT or an API key); it spends one small
// Codex turn. Gemini is only probed: no sign-in is needed. Never prints the Codex account.
@Tags(<String>['agent'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tokens.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tool.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_probe.dart';
import 'package:flutter_code_agent/src/feature/app_mcp_tools/data/skill_tools.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_servers_repository.dart';
import 'package:flutter_code_agent/src/feature/session_context/data/session_context_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/builtin_knowledge.dart';
import 'package:flutter_code_agent/src/feature/skills/data/chat_skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skills_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/flutter_version_runner.dart';
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

/// [AppMcpTool] that counts the calls reaching the app server.
final class _CountingTool implements AppMcpTool {
  _CountingTool(this._tool);

  final AppMcpTool _tool;
  int calls = 0;

  @override
  String get name => _tool.name;

  @override
  String get description => _tool.description;

  @override
  Map<String, Object?> get inputSchema => _tool.inputSchema;

  @override
  Future<AppMcpResult> call(AppMcpCaller caller, Map<String, Object?> arguments) {
    calls++;
    return _tool.call(caller, arguments);
  }
}

const String _prompt =
    'Call the list_skills tool of flutter_code_agent and reply with the number of skills.';

void main() {
  final enabled = Platform.environment['FLUTTER_AGENT_TEST'] == '1';
  final skip = enabled
      ? false
      : 'Talks to the real Codex and Gemini agents; set FLUTTER_AGENT_TEST=1';

  late Directory temp;
  late ShellEnvironment environment;
  late AppDatabase database;
  late AppMcpServerImpl server;
  late AgentHub hub;
  late AgentProbeImpl probe;
  late int projectId;
  late _CountingTool listSkills;
  var codexMode = 'agent';

  setUpAll(() async {
    if (!enabled) return;
    temp = Directory.systemTemp.createTempSync('agents_test');
    final project = Directory(p.join(temp.path, 'project'))..createSync();
    environment = await ShellEnvironment.resolve();
    // The first `npx` of a pinned package downloads it: more than the app's 60 s.
    probe = AgentProbeImpl(environment: environment, timeout: const Duration(minutes: 3));
    database = AppDatabase(NativeDatabase.memory());
    projectId = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: project.path, name: 'project'));
    final skills = SkillsRepositoryImpl(
      database: database,
      builtin: _DiskKnowledge(),
      userRoot: p.join(temp.path, 'support'),
    );
    final chatSkills = ChatSkillsRepositoryImpl(database: database);
    final catalog = ChatSkillCatalog(skills: skills, chatSkills: chatSkills);
    final tokens = AppMcpTokens(database: database);
    listSkills = _CountingTool(ListSkillsTool(catalog: catalog));
    server = AppMcpServerImpl(
      tokens: tokens,
      tools: [
        listSkills,
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
        flutterSdk: FlutterSdkRepositoryImpl(
          which: (_) => null,
          runProcess: flutterVersionRunner,
          step: Duration.zero,
        ),
      ),
      environment: environment,
    );
    hub = AgentHub(
      database: database,
      environment: environment,
      agents: {for (final agent in AgentDefinition.builtins) agent.id: agent},
      setupTimeout: const Duration(minutes: 3),
      sessionDefaults: (agentId) async => {if (agentId == 'codex') 'mode': codexMode},
      sessionContext: (sessionId, agent, initializeResult) => context.forSession(
        sessionId: sessionId,
        agent: agent,
        initializeResult: initializeResult,
      ),
    );
  });

  tearDownAll(() async {
    if (!enabled) return;
    await hub.dispose();
    await probe.dispose();
    await server.close();
    await database.close();
    temp.deleteSync(recursive: true);
  });

  test(
    'codex probe is ready and signed in',
    () async {
      final result = await probe.probe(AgentDefinition.codex);

      // Only the kind and the label: the pushed status also holds the account.
      debugPrint(
        'codex probe: version ${result.version}, failure ${result.failure}, '
        'auth ${result.authStatus?.kind} "${result.authStatus?.label}", '
        'methods ${[for (final method in result.authMethods) method.id]}, '
        'http ${result.mcpHttp}, sse ${result.mcpSse}, systemPrompt ${result.systemPrompt}, '
        'logout ${result.canLogout}',
      );
      expect(result.failure, isNull);
      expect(result.notInstalled, isFalse, reason: '${result.notInstalledReason}');
      expect(result.version, AgentDefinition.codexAdapterVersion);
      expect(result.authStatus, isNotNull, reason: 'no _auth/status_update within 3 s');
      expect(result.authStatus!.kind, isNot('none'));
      expect(result.systemPrompt, isTrue);
      expect(result.mcpHttp, isTrue);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  /// Sends [_prompt] in a new Codex chat in [mode] and checks that `list_skills` reached the app
  /// server without asking the user. Prints every permission request, the tool calls and the reply.
  ///
  /// With [appAnswers] Codex must have asked for permission and the app must have allowed it.
  Future<void> listSkillsTurn(String mode, {bool appAnswers = false}) async {
    codexMode = mode;
    final calls = listSkills.calls;
    final chat = await database
        .into(database.sessionsTable)
        .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: 'codex'));
    final live = await hub.session(chat);
    // A request the app did not answer itself waits for the user, who is not here: record it and
    // stop the turn.
    final seen = <String, int>{};
    var asked = false;
    final watch = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (asked) return;
      final pending = hub.permissions.pendingFor(chat).toSet();
      for (final event in live.store.events) {
        if (event.kind != SessionEventKind.permissionRequest) continue;
        final id = event.payload['requestId']! as String;
        if (!pending.contains(id)) continue;
        // Pending for over a second: the app did not allow it.
        if ((seen[id] = (seen[id] ?? 0) + 1) > 4) {
          asked = true;
          unawaited(hub.cancel(chat));
        }
      }
    });
    try {
      await hub.prompt(chat, _prompt).timeout(const Duration(minutes: 4));
    } finally {
      watch.cancel();
    }

    final events = live.store.events.toList();
    final resolutions = {
      for (final event in events)
        if (event.kind == SessionEventKind.permissionResolution)
          event.payload['requestId']: event.payload,
    };
    final current = live.configOptions.value.where((o) => o['id'] == 'mode').firstOrNull;
    debugPrint('codex [$mode] mode in effect: ${current?['currentValue']}');
    for (final event in events) {
      if (event.kind == SessionEventKind.permissionRequest) {
        final params = event.payload['params']! as Map<String, Object?>;
        debugPrint('codex [$mode] permission toolCall: ${jsonEncode(params['toolCall'])}');
        debugPrint('codex [$mode] permission options: ${jsonEncode(params['options'])}');
        debugPrint(
          'codex [$mode] resolution: ${jsonEncode(resolutions[event.payload['requestId']])}',
        );
      } else if (event.kind == 'tool_call') {
        debugPrint('codex [$mode] tool_call: ${jsonEncode(event.payload['params'])}');
      }
    }
    final reply = [
      for (final event in events)
        if (event.kind == 'agent_message_chunk')
          if (event.payload case {'params': {'update': {'content': {'text': final String text}}}})
            text,
    ].join();
    debugPrint('codex [$mode] reply: $reply');

    expect(asked, isFalse, reason: 'Codex asked the user for permission');
    expect(
      listSkills.calls,
      greaterThan(calls),
      reason: 'list_skills did not reach the app server',
    );
    expect(live.status.value, SessionStatus.idle, reason: 'the turn did not end');
    if (appAnswers) {
      expect(
        resolutions.values,
        contains(containsPair('outcome', 'selected')),
        reason: 'Codex asked nothing in $mode',
      );
    }
  }

  test(
    'codex calls list_skills',
    () => listSkillsTurn('agent'),
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'codex calls list_skills in a mode that asks the user',
    () => listSkillsTurn('workspace-write', appAnswers: true),
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'gemini probe reports its methods',
    () async {
      final result = await probe.probe(AgentDefinition.gemini, authStatusWait: Duration.zero);

      debugPrint(
        'gemini probe: version ${result.version}, failure ${result.failure}, '
        'methods ${[for (final method in result.authMethods) method.id]}, '
        'http ${result.mcpHttp}, sse ${result.mcpSse}, logout ${result.canLogout}',
      );
      expect(result.failure, isNull);
      expect(result.notInstalled, isFalse, reason: '${result.notInstalledReason}');
      expect([
        for (final method in result.authMethods) method.id,
      ], containsAll(<String>['oauth-personal', 'gemini-api-key', 'vertex-ai', 'gateway']));
      expect(result.mcpHttp, isTrue);
      expect(result.mcpSse, isTrue);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
