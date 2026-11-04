import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tokens.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/drop_zone/drop_zone.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_options_catalog.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_probe.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/data/custom_agents_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/run_config_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_queue_controller.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/initialization/widget/dependencies_scope.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_probe.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_servers_repository.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/data/permission_rules_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/session_context/data/session_context_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/chat_skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skills_repository.dart';

/// {@template dependencies}
/// Application dependencies.
/// {@endtemplate}
class Dependencies {
  /// {@macro dependencies}
  Dependencies();

  /// The state from the closest instance of this class.
  ///
  /// {@macro dependencies}
  factory Dependencies.of(BuildContext context) => DependenciesScope.of(context);

  /// Injest dependencies to the widgets tree.
  Widget inject({required Widget child, Key? key}) =>
      DependenciesScope(dependencies: this, key: key, child: child);

  /// Database
  late final AppDatabase database;

  /// Files dragged over the window; every chat's drop target listens.
  late final DropZone dropZone;

  /// Login-shell environment for every child process (agents, `flutter`, `git`).
  late final ShellEnvironment shellEnvironment;

  /// The settings (model, mode, …) the agents reported, kept between runs.
  late final IAgentOptionsCatalog agentOptionsCatalog;

  /// The ACP agents the user added.
  late final ICustomAgentsRepository customAgentsRepository;

  /// Agent processes and the runtime state of every chat.
  late final AgentHub agentHub;

  /// Stops feeding the built-in and custom agents into [agentHub]; called before the hub is
  /// disposed.
  late final Future<void> Function() stopFollowingCustomAgents;

  /// The message queues of the chats; a queue with messages outlives its chat's widget.
  late final ChatQueueRegistry chatQueues;

  /// Checks agents with a short ACP handshake; stopped when the app closes.
  late final IAgentProbe agentProbe;

  /// The agents, their state on this machine, and sign-in, sign-out and settings actions.
  late final IAgentsRepository agentsRepository;

  /// The devices the app can run on.
  late final IDevicesRepository devicesRepository;

  /// Runs of the projects' apps (`flutter run`).
  late final IAppRunRepository appRunRepository;

  /// The arguments each project adds to `flutter run`.
  late final IRunConfigRepository runConfigRepository;

  /// Picks a widget in a running app.
  late final IWidgetPickerRepository widgetPickerRepository;

  /// Skills and rules: the built-in ones, the user's and the projects', and where they are on.
  late final ISkillsRepository skillsRepository;

  /// Which skills a single chat turns on or off against its project.
  late final IChatSkillsRepository chatSkillsRepository;

  /// Connects to MCP servers to show their status; stopped when the app closes.
  late final IMcpProbe mcpProbe;

  /// The MCP servers handed to agents: the built-in ones and the user's own.
  late final IMcpServersRepository mcpServersRepository;

  /// The permission rules saved in each project's `.claude/settings.local.json`.
  late final IPermissionRulesRepository permissionRulesRepository;

  /// The Flutter SDK, its version and `flutter doctor`.
  late final IFlutterSdkRepository flutterSdkRepository;

  /// Creates new Flutter projects.
  late final IProjectCreationRepository projectCreationRepository;

  /// The bearer tokens that tie agents' requests to the app's MCP server to their chats.
  late final AppMcpTokens appMcpTokens;

  /// The app's own MCP server for the agents (`flutter_code_agent`).
  late final IAppMcpServer appMcpServer;

  /// The MCP servers, rules and skills every agent session of a chat starts with.
  late final ISessionContextRepository sessionContextRepository;

  @override
  String toString() => 'Dependencies{}';
}
