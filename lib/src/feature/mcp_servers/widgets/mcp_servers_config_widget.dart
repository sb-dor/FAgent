import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/controller/mcp_server_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/controller/mcp_servers_controller.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_exceptions.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/widgets/add_mcp_server_dialog.dart';
import 'package:flutter_code_agent/src/feature/projects/controller/projects_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// Gives the widgets of the MCP servers section access to [McpServersConfigWidgetState].
class McpServersConfigInhWidget extends InheritedWidget {
  const McpServersConfigInhWidget({super.key, required this.state, required super.child});

  final McpServersConfigWidgetState state;

  static McpServersConfigWidgetState of(BuildContext context) {
    final widget = context
        .getElementForInheritedWidgetOfExactType<McpServersConfigInhWidget>()
        ?.widget;
    assert(widget != null, 'McpServersConfigInhWidget was not found in element tree');
    return (widget! as McpServersConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(McpServersConfigInhWidget oldWidget) => false;
}

/// {@template mcp_servers_config_widget}
/// Owns the controllers of the MCP servers section: the list of servers and the actions on them
/// (add, remove, switch, import).
///
/// It also owns what the buttons do beyond that: asking before a server is removed, picking the
/// `.mcp.json` to import, and telling the user the outcome. A refusal of the add dialog is
/// explained by the dialog itself, so it is not repeated here.
/// {@endtemplate}
class McpServersConfigWidget extends StatefulWidget {
  /// {@macro mcp_servers_config_widget}
  const McpServersConfigWidget({required this.child, super.key});

  /// The section.
  final Widget child;

  @override
  State<McpServersConfigWidget> createState() => McpServersConfigWidgetState();
}

class McpServersConfigWidgetState extends State<McpServersConfigWidget> {
  late final McpServersController servers;
  late final McpServerActionsController actions;
  late final WorkspaceConfigWidgetState _workspace;

  /// Asks the user for a `.mcp.json`; `null` when they cancel. Tests replace it, because the native
  /// picker cannot be driven from a widget test.
  @visibleForTesting
  Future<String?> Function() pickFile = () async => (await openFile(
    acceptedTypeGroups: const <XTypeGroup>[
      XTypeGroup(label: 'JSON', extensions: <String>['json']),
    ],
  ))?.path;

  @override
  void initState() {
    super.initState();
    _workspace = WorkspaceConfigInhWidget.of(context);
    final repository = Dependencies.of(context).mcpServersRepository;
    servers = McpServersController(repository: repository)..watch();
    actions = McpServerActionsController(repository: repository)..addListener(_onAction);
  }

  @override
  void dispose() {
    actions
      ..removeListener(_onAction)
      ..dispose();
    servers.dispose();
    super.dispose();
  }

  /// Notifies when the projects change.
  Listenable get projectsListenable => _workspace.projectsController;

  /// The projects a server can be turned off in.
  List<Project> get projects => switch (_workspace.projectsController.state) {
    Projects$CompletedState(:final projects) => projects,
    _ => const <Project>[],
  };

  /// Tells the user about the result of the last action.
  void _onAction() {
    final localization = Localization.of(context);
    switch (actions.state) {
      case McpServerActions$CompletedState(:final imported?):
        final skipped = imported.skipped;
        showMessage(
          skipped.isEmpty
              ? localization.mcpImportAdded(imported.added.length)
              : localization.mcpImportAddedSkipped(
                  imported.added.length,
                  skipped.length,
                  skipped.map((entry) => entry.$1).join(', '),
                ),
        );
      // The add dialog explains what is wrong with the server itself.
      case McpServerActions$FailedState(error: InvalidMcpServerException()):
        break;
      case McpServerActions$FailedState(error: McpJsonException(:final message)):
        showMessage(localization.mcpImportFailed(message));
      case McpServerActions$FailedState(:final error):
        showMessage(localization.mcpActionFailed('$error'));
      case McpServerActions$IdleState() ||
          McpServerActions$ProcessingState() ||
          McpServerActions$CompletedState():
        break;
    }
  }

  /// Shows [message] in a snack bar.
  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Says that signing in to a server arrives with milestone M3.
  void showSignInComingSoon() => showMessage(Localization.of(context).comingInMilestone('M3'));

  /// Opens the dialog that adds a server over [transport].
  Future<void> openAddDialog(McpTransport transport) => showDialog<void>(
    context: context,
    builder: (context) => AddMcpServerDialog(scope: this, transport: transport),
  );

  /// Asks for a `.mcp.json` and adds the servers it lists.
  Future<void> importFromFile() async {
    final path = await pickFile();
    if (path != null && mounted) actions.importMcpJson(path);
  }

  /// Asks, then removes [server].
  Future<void> confirmRemove(McpServer server) async {
    final localization = Localization.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
        content: Text(localization.mcpRemoveConfirm(server.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localization.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.colors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(localization.mcpRemove),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) actions.remove(server.id);
  }

  @override
  Widget build(BuildContext context) => McpServersConfigInhWidget(state: this, child: widget.child);
}
