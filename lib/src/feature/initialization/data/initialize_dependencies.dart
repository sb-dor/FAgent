import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/controller/controller_observer.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_options_catalog.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/fake_flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/initialization/data/platform_initialization.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_servers_repository.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/data/permission_rules_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/builtin_knowledge.dart';
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
  // Stand-ins until the Flutter tooling is wired in; the real ones replace these lines.
  'Create app run repositories': (dependencies) {
    dependencies
      ..devicesRepository = FakeDevicesRepositoryImpl()
      ..appRunRepository = FakeAppRunRepositoryImpl()
      ..widgetPickerRepository = FakeWidgetPickerRepositoryImpl();
  },
  // Remembers the settings every agent reports, for the Settings screen.
  'Create agent options catalog': (dependencies) =>
      dependencies.agentOptionsCatalog = AgentOptionsCatalogImpl(database: dependencies.database),
  'Create agent hub': (dependencies) => dependencies.agentHub = AgentHub(
    database: dependencies.database,
    environment: dependencies.shellEnvironment,
    observers: <TurnObserver>[GitTurnFilesObserver(environment: dependencies.shellEnvironment)],
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
  'Create agents repository': (dependencies) =>
      dependencies.agentsRepository = AgentsRepositoryImpl(
        hub: dependencies.agentHub,
        environment: dependencies.shellEnvironment,
        catalog: dependencies.agentOptionsCatalog,
      ),
  'Create skills repository': (dependencies) async =>
      dependencies.skillsRepository = SkillsRepositoryImpl(
        database: dependencies.database,
        builtin: AssetBuiltinKnowledge(bundle: rootBundle),
        userRoot: (await getApplicationSupportDirectory()).path,
      ),
  'Create MCP servers repository': (dependencies) =>
      dependencies.mcpServersRepository = McpServersRepositoryImpl(database: dependencies.database),
  'Create permission rules repository': (dependencies) =>
      dependencies.permissionRulesRepository = PermissionRulesRepositoryImpl(),
  // The SDK path and the fvm version are real; the Flutter version and doctor are made up (M4).
  'Create Flutter SDK repository': (dependencies) => dependencies.flutterSdkRepository =
      FakeFlutterSdkRepositoryImpl(which: dependencies.shellEnvironment.which),
};
