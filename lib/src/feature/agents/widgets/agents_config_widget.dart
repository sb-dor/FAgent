import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/agents/controller/agent_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/agents/controller/agents_controller.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agents_exceptions.dart';
import 'package:flutter_code_agent/src/feature/agents/widgets/custom_agent_dialog.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';

/// Gives the widgets of the agent settings access to [AgentsConfigWidgetState].
class AgentsConfigInhWidget extends InheritedWidget {
  const AgentsConfigInhWidget({super.key, required this.state, required super.child});

  final AgentsConfigWidgetState state;

  static AgentsConfigWidgetState of(BuildContext context) {
    final widget = context.getElementForInheritedWidgetOfExactType<AgentsConfigInhWidget>()?.widget;
    assert(widget != null, 'AgentsConfigInhWidget was not found in element tree');
    return (widget! as AgentsConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(AgentsConfigInhWidget oldWidget) => false;
}

/// {@template agents_config_widget}
/// Owns the controllers of the agent settings: the list of agents with their state, and the
/// actions on them (sign-in, sign-out, the settings, the custom agents).
///
/// It asks before an action would stop a busy chat, shows the running browser sign-in, and tells
/// the user when an action failed.
/// {@endtemplate}
class AgentsConfigWidget extends StatefulWidget {
  /// {@macro agents_config_widget}
  const AgentsConfigWidget({required this.child, super.key});

  /// The settings that use the agents.
  final Widget child;

  @override
  State<AgentsConfigWidget> createState() => AgentsConfigWidgetState();
}

class AgentsConfigWidgetState extends State<AgentsConfigWidget> {
  late final AgentsController agents;
  late final AgentActionsController actions;

  @override
  void initState() {
    super.initState();
    final repository = Dependencies.of(context).agentsRepository;
    agents = AgentsController(repository: repository)..watch();
    actions = AgentActionsController(repository: repository)..addListener(_onAction);
  }

  @override
  void dispose() {
    actions
      ..removeListener(_onAction)
      ..dispose();
    agents.dispose();
    super.dispose();
  }

  /// Tells the user about a failed action, once.
  void _onAction() {
    final error = actions.state.error;
    if (error == null) return;
    final localization = Localization.of(context);
    showMessage(
      error is AgentSettingsMissingException
          ? localization.agentSettingsMissing
          : localization.agentActionFailed('$error'),
    );
    actions.acknowledge();
  }

  /// Shows [message] in a snack bar.
  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Signs [agent] in with [method]; a browser or key sign-in shows a dialog until it ends, with
  /// Cancel.
  Future<void> signIn(AgentInfo agent, AgentLoginMethod method) async {
    actions.login(agent.id, method);
    if (method.kind == AgentLoginKind.terminal || !actions.state.signingIn.contains(agent.id)) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SignInDialog(actions: actions, agent: agent),
    );
  }

  /// Signs [agent] out; asks first when that would stop a busy chat of it.
  Future<void> signOut(AgentInfo agent) async {
    final localization = Localization.of(context);
    // Claude signs out through its CLI; its chats go on.
    if (agent.id != AgentDefinition.claude.id &&
        await actions.hasBusyChats(agent.id) &&
        !await _confirm(
          localization.agentSignOutBusyConfirm(agent.name),
          localization.agentSignOut,
        )) {
      return;
    }
    actions.logout(agent.id);
  }

  /// Asks for a new custom agent and adds it.
  Future<void> addCustomAgent() async {
    final draft = await CustomAgentDialog.show(context);
    if (draft != null && mounted) actions.addCustom(draft);
  }

  /// Edits the custom [agent].
  Future<void> editCustomAgent(AgentInfo agent) async {
    final draft = await CustomAgentDialog.show(context, initial: agent.custom);
    if (draft != null && mounted) actions.updateCustom(agent.id, draft);
  }

  /// Removes the custom [agent]; asks first when a chat of it is busy.
  Future<void> removeCustomAgent(AgentInfo agent) async {
    final localization = Localization.of(context);
    if (await actions.hasBusyChats(agent.id) &&
        !await _confirm(localization.agentRemoveBusyConfirm(agent.name), localization.remove)) {
      return;
    }
    actions.removeCustom(agent.id);
  }

  /// Asks [question]; `true` when the user picks [confirm].
  Future<bool> _confirm(String question, String confirm) async {
    if (!mounted) return false;
    final localization = Localization.of(context);
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
        content: Text(question),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localization.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.colors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  @override
  Widget build(BuildContext context) => AgentsConfigInhWidget(state: this, child: widget.child);
}

/// Waits for a browser or key sign-in of [agent]; closes itself when it ends. Cancel stops it.
class _SignInDialog extends StatefulWidget {
  const _SignInDialog({required this.actions, required this.agent});

  final AgentActionsController actions;
  final AgentInfo agent;

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.actions.addListener(_onActions);
    // The sign-in may have ended before the dialog showed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onActions();
    });
  }

  @override
  void dispose() {
    widget.actions.removeListener(_onActions);
    super.dispose();
  }

  void _onActions() {
    if (_closed || widget.actions.state.signingIn.contains(widget.agent.id)) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
        title: Text(localization.agentSignInTitle(widget.agent.name)),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.accent),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(localization.agentSignInWaiting)),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => widget.actions.cancelLogin(widget.agent.id),
            child: Text(localization.cancel),
          ),
        ],
      ),
    );
  }
}
