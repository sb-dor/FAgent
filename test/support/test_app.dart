import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tokens.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tool.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_options_catalog.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_probe.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/data/custom_agents_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/run_config_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_queue_controller.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_probe.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_servers_repository.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/data/permission_rules_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/data/prompt_sending_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/chat_skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skills_repository.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'flutter_version_runner.dart';
import 'memory_agents_repository.dart';
import 'memory_devices_repository.dart';
import 'memory_permission_rules_repository.dart';
import 'memory_project_creation_repository.dart';
import 'memory_run_config_repository.dart';
import 'memory_skills_repository.dart';
import 'scripted_app_run_repository.dart';
import 'scripted_mcp_probe.dart';
import 'scripted_widget_picker_repository.dart';

/// Dependencies backed by an in-memory database; no agent is ever started. A test can pass its own
/// [appRunRepository], [devicesRepository], [widgetPickerRepository] or [runConfigRepository] (a
/// [MemoryRunConfigRepository] by default).
///
/// The run and the devices are a [ScriptedAppRunRepository] and a [MemoryDevicesRepository], both
/// marked as previews, so the Preview badges show unless the test passes real-looking ones.
///
/// The skills repository is an in-memory one with a built-in skill and rule unless the test passes
/// its own [skillsRepository]; it never touches the file system. The agents are an in-memory
/// [MemoryAgentsRepository] (a signed-in Claude and the two preview agents) unless the test passes
/// its own [agentsRepository]. The MCP servers repository runs on the in-memory database unless the
/// test passes its own [mcpServersRepository]. The chat skills repository runs on the in-memory
/// database unless the test passes its own [chatSkillsRepository]. The permission rules are an in-memory
/// [MemoryPermissionRulesRepository] without any rule unless the test passes its own
/// [permissionRulesRepository]. The Flutter SDK repository is the fake one with a `flutter` on
/// `PATH` and no delay unless the test passes its own [flutterSdkRepository]. The project creation
/// repository is a [MemoryProjectCreationRepository] unless the test passes its own
/// [projectCreationRepository]. The app's MCP server is a real one that is never started unless the
/// test passes its own [appMcpServer]. The MCP servers repository probes with a [ScriptedMcpProbe]
/// that fails every server unless the test passes its own [mcpProbe].
Dependencies testDependencies({
  Duration step = const Duration(milliseconds: 1),
  IAppRunRepository? appRunRepository,
  IDevicesRepository? devicesRepository,
  IWidgetPickerRepository? widgetPickerRepository,
  IRunConfigRepository? runConfigRepository,
  ISkillsRepository? skillsRepository,
  IChatSkillsRepository? chatSkillsRepository,
  IAgentsRepository? agentsRepository,
  IMcpServersRepository? mcpServersRepository,
  IPermissionRulesRepository? permissionRulesRepository,
  IFlutterSdkRepository? flutterSdkRepository,
  IProjectCreationRepository? projectCreationRepository,
  IAppMcpServer? appMcpServer,
  IMcpProbe? mcpProbe,
}) {
  final database = AppDatabase(NativeDatabase.memory());
  const environment = ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'});
  final appMcpTokens = AppMcpTokens(database: database);
  final appServer =
      appMcpServer ??
      AppMcpServerImpl(
        tokens: appMcpTokens,
        tools: const <AppMcpTool>[],
        instructions: appMcpInstructions,
      );
  final probe = mcpProbe ?? ScriptedMcpProbe();
  final sdkRepository =
      flutterSdkRepository ??
      FlutterSdkRepositoryImpl(
        which: (_) => '/opt/flutter/bin/flutter',
        runProcess: flutterVersionRunner,
        step: Duration.zero,
      );
  final hub = AgentHub(database: database, environment: environment);
  return Dependencies()
    ..database = database
    ..shellEnvironment = environment
    ..agentOptionsCatalog = AgentOptionsCatalogImpl(database: database)
    ..customAgentsRepository = CustomAgentsRepositoryImpl(database: database)
    ..agentHub = hub
    ..chatQueues = ChatQueueRegistry(
      create: (sessionId) => ChatQueueController(
        sessionId: sessionId,
        repository: PromptSendingRepositoryImpl(hub: hub),
      ),
    )
    ..stopFollowingCustomAgents = () async {}
    ..agentProbe = AgentProbeImpl(environment: environment)
    ..agentsRepository = agentsRepository ?? MemoryAgentsRepository()
    ..devicesRepository = devicesRepository ?? MemoryDevicesRepository(step: step, isPreview: true)
    ..appRunRepository = appRunRepository ?? ScriptedAppRunRepository(step: step, isPreview: true)
    ..widgetPickerRepository = widgetPickerRepository ?? ScriptedWidgetPickerRepository(step: step)
    ..runConfigRepository = runConfigRepository ?? MemoryRunConfigRepository()
    ..chatSkillsRepository = chatSkillsRepository ?? ChatSkillsRepositoryImpl(database: database)
    ..permissionRulesRepository = permissionRulesRepository ?? MemoryPermissionRulesRepository()
    ..projectCreationRepository = projectCreationRepository ?? MemoryProjectCreationRepository()
    ..appMcpTokens = appMcpTokens
    ..appMcpServer = appServer
    ..flutterSdkRepository = sdkRepository
    ..mcpProbe = probe
    ..mcpServersRepository =
        mcpServersRepository ??
        McpServersRepositoryImpl(
          database: database,
          appServer: appServer,
          probe: probe,
          flutterSdk: sdkRepository,
        )
    ..skillsRepository =
        skillsRepository ??
        MemorySkillsRepository(
          items: [memorySkill('feature-architecture'), memoryRule('dart-style')],
          texts: {
            'skill:builtin:feature-architecture': '# feature-architecture\n',
            'rule:builtin:dart-style': '# dart-style\n',
          },
        );
}

/// Wraps [child] in the app's localizations, [theme] (light by default) and [dependencies].
///
/// With [withSettings] the app also has the window settings (`AppSettingsConfigWidget`) that the
/// workspace widgets need. They watch the database, so such a test must end with [disposeTestApp].
///
/// [builder] wraps the app's navigator, so what it adds is an ancestor of every route.
Widget testApp(
  Widget child, {
  Dependencies? dependencies,
  Locale locale = const Locale('en'),
  ThemeData? theme,
  TransitionBuilder? builder,
  bool withSettings = false,
}) {
  final app = MaterialApp(
    theme: theme ?? AppTheme.light(),
    builder: builder,
    locale: locale,
    localizationsDelegates: const <LocalizationsDelegate<Object?>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      Localization.delegate,
    ],
    supportedLocales: Localization.supportedLocales,
    home: Scaffold(body: child),
  );
  return (dependencies ?? testDependencies()).inject(
    child: withSettings ? AppSettingsConfigWidget(child: app) : app,
  );
}

/// A desktop-sized test view.
void useDesktopView(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1280, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Unmounts the app so drift's stream subscriptions are cancelled, then lets
/// their zero-length cleanup timers fire (flutter_test fails on timers left
/// after a test). The in-memory database is simply dropped.
Future<void> disposeTestApp(WidgetTester tester, Dependencies dependencies) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
