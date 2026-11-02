import 'dart:io';

import 'package:dart_acp_sdk/dart_acp_sdk.dart' as acp;
import 'package:drift/drift.dart' show innerJoin;
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/session_context.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tokens.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_executable.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/dart_mcp_command.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_servers_repository.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:flutter_code_agent/src/feature/session_context/data/rules_prompt.dart';
import 'package:flutter_code_agent/src/feature/skills/data/chat_skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skills_for_chat.dart';
import 'package:l/l.dart';
import 'package:path/path.dart' as p;

/// The id of the app's own server in [IMcpServersRepository]; only per-project switches.
const String _appServerId = 'builtin:app';

/// The id of Dart MCP in [IMcpServersRepository]; only per-project switches.
const String _dartServerId = 'builtin:dart';

/// The name Dart MCP goes by in the agent (its tools are `mcp__dart__*`).
const String _dartServerName = 'dart';

/// The rules of [library] whose text goes into the rules prompt, in library order: the enabled
/// ones, without the project's `AGENTS.md` ([KnowledgeItem.alwaysOn]; the file goes in as
/// `agentsMd`). With [agentReadsProjectRules] the project's rules are left out too
/// ([KnowledgeItem.readByClaude]): the agent loads `.claude/rules` itself, so their text would
/// reach it twice.
List<KnowledgeItem> promptRules(SkillLibrary library, {required bool agentReadsProjectRules}) => [
  for (final rule in library.rules)
    if (rule.enabled && !rule.alwaysOn && !(agentReadsProjectRules && rule.readByClaude)) rule,
];

/// Builds the [SessionContext] of a chat.
abstract interface class ISessionContextRepository {
  /// The servers and the rules for a new or loaded agent session of the chat [sessionId], which
  /// runs [agent]; [initializeResult] is the agent's raw `initialize` result, whose
  /// `agentCapabilities.mcpCapabilities` say which server transports it takes. The project comes
  /// from the chat's `sessions` row; a chat without one throws a [StateError].
  ///
  /// Each call issues the chat a new token for the app's server, so the previous one stops working.
  Future<SessionContext> forSession({
    required int sessionId,
    required AgentDefinition agent,
    required Map<String, Object?> initializeResult,
  });
}

/// {@template session_context_repository}
/// [ISessionContextRepository] over the app's server, Dart MCP, the user's servers and the skills
/// and rules of the project.
///
/// Servers, in this order: the app's server (an `http` entry with the chat's bearer token) unless
/// it did not start or is off in the project; Dart MCP on the project's Flutter SDK unless there is
/// none or it is off in the project; then the user's servers that are on for the project, `stdio`
/// ones with the login shell's `PATH` added to their `env`. `http` servers go only to an agent
/// whose `initialize` reported `mcpCapabilities.http` (`sse` ones would need `.sse`; the app has
/// none yet); the names of the others are [SessionContext.skippedServers].
/// [SessionContext.withAppServer] says whether the app's server is among them.
///
/// The rules are [buildRulesPrompt] of [promptRules], the project's `AGENTS.md` and the app's
/// skills that are on for the chat, one per name (none without the app's server), without what
/// the agent reads itself: Claude Code reads `.claude/rules`, Codex reads `AGENTS.md`. They go
/// on the agent's [AgentDefinition.rulesChannel]: [SessionContext.systemPrompt],
/// [SessionContext.firstMessageRules], or for [RulesChannel.claudeMeta] the `_meta`:
/// * `systemPrompt.append` — the rules;
/// * `claudeCode.options.allowedTools` — the app's server, whose tools then never ask;
/// * `claudeCode.options.skills` — only while a project skill (`.claude/skills`) is off for the
///   project or the chat: the project's skills that are on. The key is an allowlist, so while it
///   is sent the user's own Claude Code skills (`~/.claude/skills`) and plugin skills are hidden
///   too; without it Claude Code shows all of its skills.
/// {@endtemplate}
final class SessionContextRepositoryImpl implements ISessionContextRepository {
  /// {@macro session_context_repository}
  ///
  /// [flutterExecutable] finds the `flutter` of a project root; by default
  /// [flutterExecutableFor] on the `PATH` of [environment].
  SessionContextRepositoryImpl({
    required this._database,
    required this._appServer,
    required this._tokens,
    required this._skills,
    required this._chatSkills,
    required this._mcpServers,
    required this._environment,
    String? Function(String projectRoot)? flutterExecutable,
  }) : _flutterExecutable =
           flutterExecutable ??
           ((projectRoot) => flutterExecutableFor(projectRoot, which: _environment.which));

  final AppDatabase _database;
  final IAppMcpServer _appServer;
  final AppMcpTokens _tokens;
  final ISkillsRepository _skills;
  final IChatSkillsRepository _chatSkills;
  final IMcpServersRepository _mcpServers;
  final ShellEnvironment _environment;
  final String? Function(String projectRoot) _flutterExecutable;

  @override
  Future<SessionContext> forSession({
    required int sessionId,
    required AgentDefinition agent,
    required Map<String, Object?> initializeResult,
  }) async {
    final (:projectId, :projectRoot) = await _projectOf(sessionId);
    final servers = await _mcpServers.watchServers().first;
    bool onHere(String id) => servers.any((s) => s.id == id && !s.disabledIn.contains(projectId));

    final mcp = switch (initializeResult['agentCapabilities']) {
      {'mcpCapabilities': final Map<Object?, Object?> mcp} => mcp,
      _ => const <Object?, Object?>{},
    };
    final takesHttp = mcp['http'] == true;
    final skipped = <String>[];
    final appUrl = _appServer.url;
    final appOn = appUrl != null && onHere(_appServerId);
    if (appOn && !takesHttp) skipped.add(appMcpServerName);
    final withApp = appOn && takesHttp;
    final dart = onHere(_dartServerId) ? _dartServer(projectRoot) : null;
    final entries = <acp.McpServer>[
      if (withApp)
        acp.McpServerMcpServerHttp(
          acp.McpServerHttp(
            name: appMcpServerName,
            url: '$appUrl',
            headers: [
              acp.HttpHeader(
                name: 'Authorization',
                value: 'Bearer ${_tokens.issue(sessionId, projectId)}',
              ),
            ],
          ),
        ),
      ?dart,
    ];
    for (final server in servers) {
      if (server.builtin || !server.enabled || server.disabledIn.contains(projectId)) continue;
      if (server.transport == McpTransport.http && !takesHttp) {
        skipped.add(server.name);
      } else if (_userServer(server) case final entry?) {
        entries.add(entry);
      }
    }

    final library = await _skills.watch(projectId: projectId, projectRoot: projectRoot).first;
    final chatStates = await _chatSkills.current(sessionId);
    final claude = agent.rulesChannel == RulesChannel.claudeMeta;
    final prompt = buildRulesPrompt(
      // Claude Code loads `.claude/rules` itself (the adapter passes the project setting source).
      rules: await _enabledRules(library, projectRoot, agentReadsProjectRules: claude),
      skills: [
        if (withApp)
          for (final skill in appSkillsByName(library, chatStates))
            (name: skill.name, description: skill.description),
      ],
      // Codex reads `AGENTS.md` itself.
      agentsMd: agent.id == AgentDefinition.codex.id
          ? null
          : await _readOrNull(p.join(projectRoot, 'AGENTS.md')),
      // Only Claude Code follows an `@AGENTS.md` import of `CLAUDE.md`.
      claudeMd: claude ? await _readOrNull(p.join(projectRoot, 'CLAUDE.md')) : null,
    );
    switch (agent.rulesChannel) {
      case RulesChannel.systemPrompt:
        return SessionContext(
          servers: entries,
          systemPrompt: prompt,
          skippedServers: skipped,
          withAppServer: withApp,
        );
      case RulesChannel.firstMessage:
        return SessionContext(
          servers: entries,
          firstMessageRules: prompt,
          skippedServers: skipped,
          withAppServer: withApp,
        );
      case RulesChannel.claudeMeta:
        break;
    }
    final projectSkills = [
      for (final skill in library.skills)
        if (skill.source == SkillSource.project) skill,
    ];
    final onForChat = {for (final skill in skillsForChat(library, chatStates)) skill.id};
    return SessionContext(
      servers: entries,
      skippedServers: skipped,
      withAppServer: withApp,
      meta: <String, Object?>{
        'systemPrompt': <String, Object?>{'append': prompt},
        'claudeCode': <String, Object?>{
          'options': <String, Object?>{
            if (withApp) 'allowedTools': <String>['mcp__$appMcpServerName'],
            // An allowlist: while it is sent, every skill not on it is hidden from Claude.
            if (projectSkills.any((skill) => !onForChat.contains(skill.id)))
              'skills': <String>[
                for (final skill in projectSkills)
                  if (onForChat.contains(skill.id)) skill.name,
              ],
          },
        },
      },
    );
  }

  Future<({int projectId, String projectRoot})> _projectOf(int sessionId) async {
    final row = await (_database.select(_database.sessionsTable).join([
      innerJoin(
        _database.projectsTable,
        _database.projectsTable.id.equalsExp(_database.sessionsTable.projectId),
      ),
    ])..where(_database.sessionsTable.id.equals(sessionId))).getSingleOrNull();
    if (row == null) throw StateError('Chat $sessionId has no project');
    final project = row.readTable(_database.projectsTable);
    return (projectId: project.id, projectRoot: project.path);
  }

  /// Dart MCP on the SDK of [projectRoot]; its `launch_app` and `stop_app` are off, so every run
  /// belongs to the Run tab.
  acp.McpServer? _dartServer(String projectRoot) {
    final flutter = _flutterExecutable(projectRoot);
    final sdk = flutter == null ? null : flutterSdkRootOf(flutter);
    if (sdk == null) return null;
    final (:command, :args) = dartMcpCommand(sdk);
    return acp.McpServerStdioVariant(
      acp.McpServerStdio(name: _dartServerName, command: command, args: args, env: _env(const {})),
    );
  }

  acp.McpServer? _userServer(McpServer server) {
    switch (server.transport) {
      case McpTransport.stdio:
        final command = server.command;
        if (command == null || command.isEmpty) return null;
        return acp.McpServerStdioVariant(
          acp.McpServerStdio(
            name: server.name,
            command: command,
            args: server.args,
            env: _env(server.env),
          ),
        );
      case McpTransport.http:
        final url = server.url;
        if (url == null || url.isEmpty) return null;
        return acp.McpServerMcpServerHttp(
          acp.McpServerHttp(
            name: server.name,
            url: url,
            headers: [
              for (final MapEntry(:key, :value) in server.headers.entries)
                acp.HttpHeader(name: key, value: value),
            ],
          ),
        );
    }
  }

  /// [env] with the login shell's `PATH` added; a `PATH` of [env] wins.
  List<acp.EnvVariable> _env(Map<String, String> env) {
    final path = _environment.variables['PATH'];
    return [
      for (final MapEntry(:key, :value) in {'PATH': ?path, ...env}.entries)
        acp.EnvVariable(name: key, value: value),
    ];
  }

  /// The texts of [promptRules] in library order. A rule that cannot be read is logged and
  /// skipped.
  Future<List<RuleText>> _enabledRules(
    SkillLibrary library,
    String projectRoot, {
    required bool agentReadsProjectRules,
  }) async {
    final rules = <RuleText>[];
    for (final rule in promptRules(library, agentReadsProjectRules: agentReadsProjectRules)) {
      try {
        final text = await _skills.read(rule.id, projectRoot: projectRoot);
        rules.add((source: rule.source, name: rule.name, text: text));
      } on Object catch (error) {
        l.w('Session context | skipping the rule ${rule.id}: $error');
      }
    }
    return rules;
  }

  static Future<String?> _readOrNull(String path) async {
    try {
      return await File(path).readAsString();
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }
}
