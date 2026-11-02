import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tokens.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tool.dart';
import 'package:flutter_code_agent/src/common/controller/controller_observer.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_executable.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_options_catalog.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_probe.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/data/custom_agents_repository.dart';
import 'package:flutter_code_agent/src/feature/app_mcp_tools/data/run_tools.dart';
import 'package:flutter_code_agent/src/feature/app_mcp_tools/data/skill_tools.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/run_config_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/initialization/data/platform_initialization.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_probe.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_servers_repository.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/data/permission_rules_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/project_opening/data/project_opening_repository.dart';
import 'package:flutter_code_agent/src/feature/project_trust/data/project_trust_repository.dart';
import 'package:flutter_code_agent/src/feature/session_context/data/session_context_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/builtin_knowledge.dart';
import 'package:flutter_code_agent/src/feature/skills/data/chat_skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skills_repository.dart';
import 'package:flutter_code_agent/src/feature/turn_files/data/git_turn_files_observer.dart';
import 'package:l/l.dart';
import 'package:path_provider/path_provider.dart';

/// Initializes the app and returns a [Dependencies] object
Future<Dependencies> $initializeDependencies({
  void Function(int progress, String message)? onProgress,
}) async {
  final dependencies = Dependencies();
  final totalSteps = _initializationSteps.length;
  var currentStep = 0;
  for (final step in _initializationSteps.entries) {
    try {
      currentStep++;
      final percent = (currentStep * 100 ~/ totalSteps).clamp(0, 100);
      onProgress?.call(percent, step.key);
      l.v6('Initialization | $currentStep/$totalSteps ($percent%) | "${step.key}"');
      await step.value(dependencies);
    } on Object catch (error, stackTrace) {
      l.e('Initialization failed at step "${step.key}": $error', stackTrace);
      Error.throwWithStackTrace('Initialization failed at step "${step.key}": $error', stackTrace);
    }
  }
  return dependencies;
}

typedef _InitializationStep = FutureOr<void> Function(Dependencies dependencies);

final Map<String, _InitializationStep> _initializationSteps = <String, _InitializationStep>{
  'Platform pre-initialization': (_) => $platformInitialization(),
  'Observer state management': (_) => Controller.observer = const ControllerObserver(),
  'Connect to database': (dependencies) =>
      dependencies.database = AppDatabase.defaults(name: 'app_database'),
  'Resolve shell environment': (dependencies) async =>
      dependencies.shellEnvironment = await ShellEnvironment.resolve(),
  // The devices and the runs are real (`flutter daemon`, `flutter run --machine`); the widget
  // picker is made up until the inspector is wired in (M6).
  'Create app run repositories': (dependencies) {
    final database = dependencies.database;
    final environment = dependencies.shellEnvironment;
    dependencies
      ..devicesRepository = DevicesRepositoryImpl(
        flutter: () => flutterExecutableFor(null, which: environment.which),
        environment: environment.variables,
      )
      ..appRunRepository = AppRunRepositoryImpl(
        projectPath: (projectId) async => (await (database.select(
          database.projectsTable,
        )..where((project) => project.id.equals(projectId))).getSingleOrNull())?.path,
        flutter: (path) => flutterExecutableFor(path, which: environment.which),
        environment: environment.variables,
      )
      ..widgetPickerRepository = FakeWidgetPickerRepositoryImpl();
  },
  // Remembers the settings every agent reports, for the Settings screen.
  'Create agent options catalog': (dependencies) =>
      dependencies.agentOptionsCatalog = AgentOptionsCatalogImpl(database: dependencies.database),
  // The ACP agents the user added; the hub follows them.
  'Create custom agents repository': (dependencies) => dependencies.customAgentsRepository =
      CustomAgentsRepositoryImpl(database: dependencies.database),
  'Create agent hub': (dependencies) => dependencies.agentHub = AgentHub(
    database: dependencies.database,
    environment: dependencies.shellEnvironment,
    agents: <String, AgentDefinition>{
      for (final agent in AgentDefinition.builtins) agent.id: agent,
    },
    observers: <TurnObserver>[GitTurnFilesObserver(environment: dependencies.shellEnvironment)],
    // Read when a chat starts its agent session, after initialization has finished.
    sessionContext: (sessionId, agent) =>
        dependencies.sessionContextRepository.forSession(sessionId: sessionId, agent: agent),
    sessionDefaults: (agentId) async =>
        (await AppSettingsRepositoryImpl(
          database: dependencies.database,
        ).watch().first).sessionDefaults[agentId] ??
        const <String, String>{},
    onConfigOptions: (agentId, options) => dependencies.agentOptionsCatalog
        .save(agentId, options)
        .catchError(
          (Object error, StackTrace stackTrace) =>
              l.w('Agent options | could not save the options of $agentId: $error', stackTrace),
        ),
  ),
  // Waits for the first list, so a chat of a custom agent opened at startup finds its agent.
  'Follow custom agents': (dependencies) async {
    final hub = dependencies.agentHub;
    final first = Completer<void>();
    final subscription = dependencies.customAgentsRepository.watch().listen(
      (custom) {
        hub.setAgents(<AgentDefinition>[...AgentDefinition.builtins, ...custom]);
        if (!first.isCompleted) first.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        l.w('Custom agents | could not read them: $error', stackTrace);
        if (!first.isCompleted) first.complete();
      },
    );
    dependencies.stopFollowingCustomAgents = subscription.cancel;
    await first.future.timeout(const Duration(seconds: 5), onTimeout: () {});
  },
  // Every agent is checked once in the background; Settings → Agents checks again when it opens.
  'Create agents repository': (dependencies) {
    final probe = AgentProbeImpl(environment: dependencies.shellEnvironment);
    final repository = AgentsRepositoryImpl(
      hub: dependencies.agentHub,
      environment: dependencies.shellEnvironment,
      catalog: dependencies.agentOptionsCatalog,
      customAgents: dependencies.customAgentsRepository,
      probe: probe,
    );
    dependencies
      ..agentProbe = probe
      ..agentsRepository = repository;
    unawaited(repository.refreshAll());
  },
  'Create skills repository': (dependencies) async =>
      dependencies.skillsRepository = SkillsRepositoryImpl(
        database: dependencies.database,
        builtin: AssetBuiltinKnowledge(bundle: rootBundle),
        userRoot: (await getApplicationSupportDirectory()).path,
      ),
  'Create chat skills repository': (dependencies) =>
      dependencies.chatSkillsRepository = ChatSkillsRepositoryImpl(database: dependencies.database),
  'Create run config repository': (dependencies) =>
      dependencies.runConfigRepository = RunConfigRepositoryImpl(database: dependencies.database),
  // The SDK path, the Flutter version and the fvm version are real; the doctor report is made up.
  'Create Flutter SDK repository': (dependencies) =>
      dependencies.flutterSdkRepository = FlutterSdkRepositoryImpl(
        which: dependencies.shellEnvironment.which,
        environment: dependencies.shellEnvironment.variables,
      ),
  // A server that cannot start leaves the app working without its tools (a hub notice says so).
  'App MCP server': (dependencies) async {
    final database = dependencies.database;
    final runs = dependencies.appRunRepository;
    final builtin = AssetBuiltinKnowledge(bundle: rootBundle);
    final catalog = ChatSkillCatalog(
      skills: dependencies.skillsRepository,
      chatSkills: dependencies.chatSkillsRepository,
    );
    final tokens = AppMcpTokens(database: database);
    final server = AppMcpServerImpl(
      tokens: tokens,
      tools: <AppMcpTool>[
        ListSkillsTool(catalog: catalog),
        LoadSkillTool(catalog: catalog, skills: dependencies.skillsRepository),
        ReadSkillFileTool(catalog: catalog, builtin: builtin),
        AppStatusTool(runs: runs),
        AppLogsTool(runs: runs),
        RuntimeErrorsTool(runs: runs),
        HotReloadTool(runs: runs),
        HotRestartTool(runs: runs),
        ScreenshotTool(
          runs: runs,
          projectRoot: (projectId) async => (await (database.select(
            database.projectsTable,
          )..where((project) => project.id.equals(projectId))).getSingleOrNull())?.path,
        ),
      ],
      instructions: appMcpInstructions,
    );
    await server.start();
    dependencies
      ..appMcpTokens = tokens
      ..appMcpServer = server;
  },
  // The status of the servers in Settings: the app's server is read, the others are probed.
  'Create MCP servers repository': (dependencies) {
    final probe = McpProbeImpl(environment: dependencies.shellEnvironment);
    dependencies
      ..mcpProbe = probe
      ..mcpServersRepository = McpServersRepositoryImpl(
        database: dependencies.database,
        appServer: dependencies.appMcpServer,
        probe: probe,
        flutterSdk: dependencies.flutterSdkRepository,
      );
  },
  'Create session context repository': (dependencies) =>
      dependencies.sessionContextRepository = SessionContextRepositoryImpl(
        database: dependencies.database,
        appServer: dependencies.appMcpServer,
        tokens: dependencies.appMcpTokens,
        skills: dependencies.skillsRepository,
        chatSkills: dependencies.chatSkillsRepository,
        mcpServers: dependencies.mcpServersRepository,
        environment: dependencies.shellEnvironment,
      ),
  'Create permission rules repository': (dependencies) =>
      dependencies.permissionRulesRepository = PermissionRulesRepositoryImpl(),
  // After the Flutter SDK repository and the shell environment: it runs `flutter` and `git`.
  'Create project creation repository': (dependencies) =>
      dependencies.projectCreationRepository = ProjectCreationRepositoryImpl(
        database: dependencies.database,
        flutterSdk: dependencies.flutterSdkRepository,
        environment: dependencies.shellEnvironment,
        projectOpening: ProjectOpeningRepositoryImpl(database: dependencies.database),
        projectTrust: ProjectTrustRepositoryImpl(database: dependencies.database),
        loadAsset: rootBundle.loadString,
      ),
};
