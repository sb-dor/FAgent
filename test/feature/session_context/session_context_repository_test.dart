import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/session_context.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tokens.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/fake_flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_servers_repository.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:flutter_code_agent/src/feature/session_context/data/rules_prompt.dart';
import 'package:flutter_code_agent/src/feature/session_context/data/session_context_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/chat_skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/memory_skills_repository.dart';
import '../../support/scripted_mcp_probe.dart';

final class _ChatSkills implements IChatSkillsRepository {
  final Map<String, bool> states = <String, bool>{};

  @override
  Future<Map<String, bool>> current(int sessionId) async => Map.of(states);

  @override
  Stream<Map<String, bool>> watch(int sessionId) => throw UnimplementedError();

  @override
  Future<void> set(
    int sessionId,
    String skillId, {
    required bool enabled,
    required bool projectEnabled,
  }) => throw UnimplementedError();
}

final class _AppServer implements IAppMcpServer {
  _AppServer(this.url);

  @override
  Uri? url;

  @override
  int get toolCount => 9;

  @override
  Object? get startError => url == null ? StateError('port is taken') : null;

  @override
  Future<void> start() async {}

  @override
  Future<void> close() async {}
}

const AgentDefinition _otherAgent = AgentDefinition(
  id: 'other',
  displayName: 'Other agent',
  executable: 'other',
);

void main() {
  late Directory temp;
  late Directory projectDir;
  late Directory sdk;
  late AppDatabase database;
  late AppMcpTokens tokens;
  late MemorySkillsRepository skills;
  late _ChatSkills chatSkills;
  late McpServersRepositoryImpl mcpServers;
  late _AppServer appServer;
  late int projectId;
  late int chatId;
  String? flutter;

  const shellPath = '/shell/bin:/usr/bin';
  const environment = ShellEnvironment(<String, String>{'PATH': shellPath, 'HOME': '/home/me'});

  KnowledgeItem projectItem(KnowledgeKind kind, String name, {String description = ''}) =>
      KnowledgeItem(
        id: '${kind.name}:project:$name',
        kind: kind,
        source: SkillSource.project,
        name: name,
        title: name,
        description: description,
        path: p.join(projectDir.path, '.claude', name),
      );

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('session_context_test');
    projectDir = Directory(p.join(temp.path, 'project'))..createSync();
    sdk = Directory(p.join(temp.path, 'flutter'));
    File(p.join(sdk.path, 'bin', 'flutter')).createSync(recursive: true);
    File(p.join(sdk.path, 'bin', 'dart')).createSync(recursive: true);
    flutter = p.join(sdk.path, 'bin', 'flutter');

    database = AppDatabase(NativeDatabase.memory());
    projectId = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: projectDir.path, name: 'project'));
    chatId = await database
        .into(database.sessionsTable)
        .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: 'claude'));
    tokens = AppMcpTokens(database: database);
    appServer = _AppServer(Uri.parse('http://127.0.0.1:4321/mcp'));
    chatSkills = _ChatSkills();
    mcpServers = McpServersRepositoryImpl(
      database: database,
      appServer: appServer,
      probe: ScriptedMcpProbe(),
      flutterSdk: FakeFlutterSdkRepositoryImpl(which: (_) => flutter, step: Duration.zero),
    );
    skills = MemorySkillsRepository(
      items: [
        memoryRule('base'),
        memoryRule('style', source: SkillSource.user),
        memoryRule('off', source: SkillSource.user),
        memorySkill('arch', description: 'Architecture'),
        memorySkill('chat-off', description: 'Off in this chat'),
        memorySkill('mine', source: SkillSource.user, description: 'My own'),
      ],
      projectItems: {
        projectDir.path: [
          projectItem(KnowledgeKind.skill, 'proj', description: 'Project skill'),
          projectItem(KnowledgeKind.skill, 'proj-off'),
          projectItem(KnowledgeKind.skill, 'proj-chat-off'),
          projectItem(KnowledgeKind.rule, 'team'),
          projectItem(KnowledgeKind.rule, 'AGENTS').copyWith(readOnly: true),
        ],
      },
      texts: {
        'rule:builtin:base': '---\nname: base\ndescription: Base\n---\nBase rule text',
        'rule:user:style': '---\nname: style\ndescription: Style\n---\nStyle rule text',
        'rule:user:off': 'Off rule text',
        'rule:project:team': 'Team rule text',
        'rule:project:AGENTS': 'AGENTS rule item text',
        'skill:builtin:arch': '',
        'skill:builtin:chat-off': '',
        'skill:user:mine': '',
        'skill:project:proj': '',
        'skill:project:proj-off': '',
        'skill:project:proj-chat-off': '',
      },
    );
    await skills.setEnabled('rule:user:off', enabled: false);
    await skills.setEnabled('skill:project:proj-off', enabled: false, projectId: projectId);
    chatSkills.states
      ..['skill:builtin:chat-off'] = false
      ..['skill:project:proj-chat-off'] = false;
    File(p.join(projectDir.path, 'AGENTS.md')).writeAsStringSync('Agents file text');
    File(p.join(projectDir.path, 'CLAUDE.md')).writeAsStringSync('# Claude\n');
  });

  tearDown(() async {
    await database.close();
    temp.deleteSync(recursive: true);
  });

  SessionContextRepositoryImpl repository() => SessionContextRepositoryImpl(
    database: database,
    appServer: appServer,
    tokens: tokens,
    skills: skills,
    chatSkills: chatSkills,
    mcpServers: mcpServers,
    environment: environment,
    flutterExecutable: (projectRoot) {
      expect(projectRoot, projectDir.path);
      return flutter;
    },
  );

  Future<SessionContext> context({AgentDefinition agent = AgentDefinition.claude}) =>
      repository().forSession(sessionId: chatId, agent: agent);

  Map<String, Object?>? serverNamed(SessionContext context, String name) => context.servers
      .map((server) => server.toJson()! as Map<String, Object?>)
      .where((json) => json['name'] == name)
      .firstOrNull;

  List<String> names(SessionContext context) => [
    for (final server in context.servers)
      (server.toJson()! as Map<String, Object?>)['name']! as String,
  ];

  String appendOf(SessionContext context) =>
      (context.meta!['systemPrompt']! as Map<String, Object?>)['append']! as String;

  Map<String, Object?> optionsOf(SessionContext context) =>
      (context.meta!['claudeCode']! as Map<String, Object?>)['options']! as Map<String, Object?>;

  group('servers', () {
    test('the app server is an http entry with the chat token', () async {
      final result = await context();

      final app = serverNamed(result, appMcpServerName)!;
      expect(app['type'], 'http');
      expect(app['url'], 'http://127.0.0.1:4321/mcp');
      final headers = (app['headers']! as List<Object?>).cast<Map<String, Object?>>();
      expect(headers, hasLength(1));
      expect(headers.single['name'], 'Authorization');
      final value = headers.single['value']! as String;
      expect(value, startsWith('Bearer '));
      expect(await tokens.resolve(value.substring('Bearer '.length)), (
        sessionId: chatId,
        projectId: projectId,
      ));
    });

    test('every call issues a new token and the old one stops working', () async {
      String token(SessionContext context) {
        final app = serverNamed(context, appMcpServerName)!;
        final header = (app['headers']! as List<Object?>).single! as Map<String, Object?>;
        return (header['value']! as String).substring('Bearer '.length);
      }

      final first = token(await context());
      final second = token(await context());

      expect(second, isNot(first));
      expect(await tokens.resolve(first), isNull);
      expect(await tokens.resolve(second), isNotNull);
    });

    test('Dart MCP is a stdio entry on the project SDK with launch and stop disabled', () async {
      final result = await context();

      final dart = serverNamed(result, 'dart')!;
      final root = File(flutter!).resolveSymbolicLinksSync().split('/bin/').first;
      expect(dart.containsKey('type'), isFalse);
      expect(dart['command'], p.join(root, 'bin', 'dart'));
      expect(dart['args'], <String>[
        'mcp-server',
        '--flutter-sdk',
        root,
        '--disable',
        'launch_app,stop_app',
      ]);
      expect(dart['env'], <Object?>[
        <String, Object?>{'name': 'PATH', 'value': shellPath},
      ]);
    });

    test('the SDK root is found through a symlinked flutter', () async {
      final link = Link(p.join(temp.path, 'bin', 'flutter'))
        ..createSync(p.join(sdk.path, 'bin', 'flutter'), recursive: true);
      flutter = link.path;

      final dart = serverNamed(await context(), 'dart')!;

      final root = Directory(sdk.path).resolveSymbolicLinksSync();
      expect(dart['command'], p.join(root, 'bin', 'dart'));
      expect((dart['args']! as List<Object?>)[2], root);
    });

    test('no flutter for the project means no Dart MCP entry', () async {
      flutter = null;

      final result = await context();

      expect(serverNamed(result, 'dart'), isNull);
      expect(serverNamed(result, appMcpServerName), isNotNull);
    });

    test('a flutter without a dart next to it means no Dart MCP entry', () async {
      File(p.join(sdk.path, 'bin', 'dart')).deleteSync();

      expect(serverNamed(await context(), 'dart'), isNull);
    });

    test('an enabled user stdio server gets the shell PATH; http keeps its headers', () async {
      await mcpServers.add(
        const McpServerDraft(
          name: 'tool',
          transport: McpTransport.stdio,
          command: 'npx',
          args: ['-y', 'tool'],
          env: {'TOKEN': 'abc'},
        ),
      );
      await mcpServers.add(
        const McpServerDraft(
          name: 'remote',
          transport: McpTransport.http,
          url: 'https://example.com/mcp',
          headers: {'X-Key': 'k'},
        ),
      );

      final result = await context();

      expect(names(result), [appMcpServerName, 'dart', 'tool', 'remote']);
      final tool = serverNamed(result, 'tool')!;
      expect(tool['command'], 'npx');
      expect(tool['args'], ['-y', 'tool']);
      expect(
        tool['env'],
        unorderedEquals(<Object?>[
          <String, Object?>{'name': 'TOKEN', 'value': 'abc'},
          <String, Object?>{'name': 'PATH', 'value': shellPath},
        ]),
      );
      expect(serverNamed(result, 'remote'), <String, Object?>{
        'name': 'remote',
        'url': 'https://example.com/mcp',
        'headers': <Object?>[
          <String, Object?>{'name': 'X-Key', 'value': 'k'},
        ],
        'type': 'http',
      });
    });

    test("a user server's own PATH wins over the shell PATH", () async {
      await mcpServers.add(
        const McpServerDraft(
          name: 'tool',
          transport: McpTransport.stdio,
          command: '/bin/tool',
          env: {'PATH': '/mine'},
        ),
      );

      expect(serverNamed(await context(), 'tool')!['env'], <Object?>[
        <String, Object?>{'name': 'PATH', 'value': '/mine'},
      ]);
    });

    test('a user server that is off globally or in the project is left out', () async {
      final global = await mcpServers.add(
        const McpServerDraft(name: 'global-off', transport: McpTransport.stdio, command: 'a'),
      );
      final here = await mcpServers.add(
        const McpServerDraft(name: 'off-here', transport: McpTransport.stdio, command: 'b'),
      );
      final elsewhere = await mcpServers.add(
        const McpServerDraft(name: 'off-elsewhere', transport: McpTransport.stdio, command: 'c'),
      );
      await mcpServers.setEnabled(global.id, enabled: false);
      await mcpServers.setEnabled(here.id, enabled: false, projectId: projectId);
      final otherProject = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/other', name: 'other'));
      await mcpServers.setEnabled(elsewhere.id, enabled: false, projectId: otherProject);

      expect(names(await context()), [appMcpServerName, 'dart', 'off-elsewhere']);
    });

    test('built-in servers switched off in the project are left out', () async {
      await mcpServers.setEnabled('builtin:app', enabled: false, projectId: projectId);
      await mcpServers.setEnabled('builtin:dart', enabled: false, projectId: projectId);

      final result = await context();

      expect(result.servers, isEmpty);
      expect(appendOf(result), isNot(contains('Skills from flutter_code_agent')));
      expect(optionsOf(result).containsKey('allowedTools'), isFalse);
    });

    test('an app server that did not start means no app entry and no skills section', () async {
      appServer.url = null;
      flutter = null;

      final result = await context();

      expect(result.servers, isEmpty);
      expect(appendOf(result), isNot(contains('Skills from flutter_code_agent')));
      expect(appendOf(result), contains('Base rule text'));
      expect(optionsOf(result).containsKey('allowedTools'), isFalse);
    });

    test('an agent without Claude meta gets the servers and no meta', () async {
      final result = await context(agent: _otherAgent);

      expect(names(result), [appMcpServerName, 'dart']);
      expect(result.meta, isNull);
    });

    test('a session without a row throws', () async {
      await expectLater(
        repository().forSession(sessionId: chatId + 100, agent: AgentDefinition.claude),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('meta', () {
    test('systemPrompt.append is the rules prompt of the enabled rules and app skills', () async {
      final result = await context();

      expect(
        appendOf(result),
        buildRulesPrompt(
          rules: [
            (
              source: SkillSource.builtin,
              name: 'base',
              text: '---\nname: base\ndescription: Base\n---\nBase rule text',
            ),
            (
              source: SkillSource.user,
              name: 'style',
              text: '---\nname: style\ndescription: Style\n---\nStyle rule text',
            ),
          ],
          skills: [
            (name: 'arch', description: 'Architecture'),
            (name: 'mine', description: 'My own'),
          ],
          agentsMd: 'Agents file text',
          claudeMd: '# Claude\n',
        ),
      );
      expect(appendOf(result), isNot(contains('AGENTS rule item text')));
      expect('Agents file text'.allMatches(appendOf(result)), hasLength(1));
    });

    test('project rules are left to Claude, which reads .claude/rules itself', () async {
      final append = appendOf(await context());

      expect(append, isNot(contains('Team rule text')));
      expect(append, isNot(contains('## team')));
      expect(append, contains('Style rule text'));
    });

    test('a user copy of a built-in skill is listed once, as the user copy', () async {
      skills = MemorySkillsRepository(
        items: [
          memorySkill('arch', description: 'Architecture'),
          memorySkill('arch', source: SkillSource.user, description: 'My architecture'),
        ],
        texts: {'skill:builtin:arch': '', 'skill:user:arch': ''},
      );

      final append = appendOf(await context());

      expect(append, contains('- arch — My architecture'));
      expect('- arch '.allMatches(append), hasLength(1));
    });

    test('AGENTS.md is left out when CLAUDE.md imports it', () async {
      File(p.join(projectDir.path, 'CLAUDE.md')).writeAsStringSync('@AGENTS.md\n');

      expect(appendOf(await context()), isNot(contains('Agents file text')));
    });

    test('a project without AGENTS.md and CLAUDE.md still gets the rules', () async {
      File(p.join(projectDir.path, 'AGENTS.md')).deleteSync();
      File(p.join(projectDir.path, 'CLAUDE.md')).deleteSync();

      final append = appendOf(await context());

      expect(append, contains('Style rule text'));
      expect(append, isNot(contains('## AGENTS.md')));
    });

    test('a rule that cannot be read is skipped', () async {
      skills = MemorySkillsRepository(
        // `unreadable` has no text, so reading it fails.
        items: [
          memoryRule('base'),
          memoryRule('unreadable', source: SkillSource.user),
        ],
        texts: {'rule:builtin:base': 'Base rule text'},
      );

      final append = appendOf(await context());

      expect(append, contains('Base rule text'));
      expect(append, isNot(contains('## unreadable')));
    });

    test('allowedTools lets the app tools run without asking', () async {
      expect(optionsOf(await context())['allowedTools'], ['mcp__flutter_code_agent']);
    });

    test('skills is left out while no project skill is off', () async {
      await skills.setEnabled('skill:project:proj-off', enabled: true, projectId: projectId);
      chatSkills.states.remove('skill:project:proj-chat-off');

      expect(optionsOf(await context()).containsKey('skills'), isFalse);
    });

    test('a project skill off in the project sends the ones that are on', () async {
      chatSkills.states.remove('skill:project:proj-chat-off');

      expect(optionsOf(await context())['skills'], ['proj', 'proj-chat-off']);
    });

    test('a project skill off in the chat sends the ones that are on', () async {
      await skills.setEnabled('skill:project:proj-off', enabled: true, projectId: projectId);

      expect(optionsOf(await context())['skills'], ['proj', 'proj-off']);
    });

    test('skills off in the project and in the chat leave only the rest', () async {
      expect(optionsOf(await context())['skills'], ['proj']);
    });

    test('a built-in or user skill off does not send skills', () async {
      await skills.setEnabled('skill:project:proj-off', enabled: true, projectId: projectId);
      chatSkills.states.remove('skill:project:proj-chat-off');
      // `chat-off` (built-in) stays off in the chat.

      expect(optionsOf(await context()).containsKey('skills'), isFalse);
    });
  });

  group('promptRules', () {
    KnowledgeItem rule(String name, {SkillSource source = SkillSource.project}) =>
        memoryRule(name, source: source);

    test('leaves out the root AGENTS.md but keeps .claude/rules/AGENTS.md', () {
      final rootAgents = SkillLibrary(rules: [rule('AGENTS').copyWith(readOnly: true)]);
      final rulesAgents = SkillLibrary(rules: [rule('AGENTS')]);

      expect(promptRules(rootAgents, agentReadsProjectRules: false), isEmpty);
      expect(
        [for (final it in promptRules(rulesAgents, agentReadsProjectRules: false)) it.id],
        ['rule:project:AGENTS'],
      );
    });

    test('leaves out the project rules for an agent that reads them itself', () {
      final library = SkillLibrary(
        rules: [
          rule('base', source: SkillSource.builtin),
          rule('style', source: SkillSource.user),
          rule('team'),
          rule('AGENTS'),
        ],
      );

      expect(
        [for (final it in promptRules(library, agentReadsProjectRules: true)) it.name],
        ['base', 'style'],
      );
      expect(
        [for (final it in promptRules(library, agentReadsProjectRules: false)) it.name],
        ['base', 'style', 'team', 'AGENTS'],
      );
    });

    test('leaves out a rule that is off', () {
      final library = SkillLibrary(
        rules: [rule('style', source: SkillSource.user).copyWith(enabled: false)],
      );

      expect(promptRules(library, agentReadsProjectRules: false), isEmpty);
    });
  });
}
