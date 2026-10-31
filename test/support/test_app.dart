import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_options_catalog.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/fake_flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_servers_repository.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/data/permission_rules_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skills_repository.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'memory_agents_repository.dart';
import 'memory_permission_rules_repository.dart';
import 'memory_skills_repository.dart';

/// Dependencies backed by an in-memory database; no agent is ever started. A test can pass its own
/// [appRunRepository], [devicesRepository] or [widgetPickerRepository].
///
/// The skills repository is an in-memory one with a built-in skill and rule unless the test passes
/// its own [skillsRepository]; it never touches the file system. The agents are an in-memory
/// [MemoryAgentsRepository] (a signed-in Claude and the two preview agents) unless the test passes
/// its own [agentsRepository]. The MCP servers repository runs on the in-memory database unless the
/// test passes its own [mcpServersRepository]. The permission rules are an in-memory
/// [MemoryPermissionRulesRepository] without any rule unless the test passes its own
/// [permissionRulesRepository]. The Flutter SDK repository is the fake one with a `flutter` on
/// `PATH` and no delay unless the test passes its own [flutterSdkRepository].
Dependencies testDependencies({
  Duration step = const Duration(milliseconds: 1),
  IAppRunRepository? appRunRepository,
  IDevicesRepository? devicesRepository,
  IWidgetPickerRepository? widgetPickerRepository,
  ISkillsRepository? skillsRepository,
  IAgentsRepository? agentsRepository,
  IMcpServersRepository? mcpServersRepository,
  IPermissionRulesRepository? permissionRulesRepository,
  IFlutterSdkRepository? flutterSdkRepository,
}) {
  final database = AppDatabase(NativeDatabase.memory());
  const environment = ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'});
  return Dependencies()
    ..database = database
    ..shellEnvironment = environment
    ..agentOptionsCatalog = AgentOptionsCatalogImpl(database: database)
    ..agentHub = AgentHub(database: database, environment: environment)
    ..agentsRepository = agentsRepository ?? MemoryAgentsRepository()
    ..devicesRepository = devicesRepository ?? FakeDevicesRepositoryImpl(step: step)
    ..appRunRepository = appRunRepository ?? FakeAppRunRepositoryImpl(step: step)
    ..widgetPickerRepository = widgetPickerRepository ?? FakeWidgetPickerRepositoryImpl(step: step)
    ..mcpServersRepository = mcpServersRepository ?? McpServersRepositoryImpl(database: database)
    ..permissionRulesRepository = permissionRulesRepository ?? MemoryPermissionRulesRepository()
    ..flutterSdkRepository =
        flutterSdkRepository ??
        FakeFlutterSdkRepositoryImpl(which: (_) => '/opt/flutter/bin/flutter', step: Duration.zero)
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
