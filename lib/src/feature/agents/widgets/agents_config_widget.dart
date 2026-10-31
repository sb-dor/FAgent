import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/agents/controller/agent_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/agents/controller/agents_controller.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agents_exceptions.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';

/// Gives the widgets of the agent settings access to [AgentsConfigWidgetState].
class AgentsConfigInhWidget extends InheritedWidget {
  const AgentsConfigInhWidget({super.key, required this.state, required super.child});

  final AgentsConfigWidgetState state;

  static AgentsConfigWidgetState of(BuildContext context) {
    final widget = context
        .getElementForInheritedWidgetOfExactType<AgentsConfigInhWidget>()
        ?.widget;
    assert(widget != null, 'AgentsConfigInhWidget was not found in element tree');
    return (widget! as AgentsConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(AgentsConfigInhWidget oldWidget) => false;
}

/// {@template agents_config_widget}
/// Owns the controllers of the agent settings: the list of agents with their state, and the
/// actions on them (login, logout, install, open the settings).
///
/// It also tells the user what an action that did not work out means: a preview agent says which
/// milestone brings the feature, anything else is shown as an error.
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

  /// Tells the user about the result of the last action, once.
  void _onAction() {
    final state = actions.state;
    final milestone = state.previewMilestone;
    final error = state.error;
    if (milestone == null && error == null) return;
    final localization = Localization.of(context);
    showMessage(
      milestone != null
          ? localization.comingInMilestone(milestone)
          : error is AgentSettingsMissingException
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

  /// Says that adding an own ACP agent arrives with milestone M5.
  void showCustomAgentComingSoon() => showMessage(Localization.of(context).comingInMilestone('M5'));

  @override
  Widget build(BuildContext context) => AgentsConfigInhWidget(state: this, child: widget.child);
}
