import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/compact_button.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/feature/agents/controller/agents_controller.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/widgets/agent_card.dart';
import 'package:flutter_code_agent/src/feature/agents/widgets/agents_config_widget.dart';

/// {@template agents_settings_section}
/// The "Agents" section of Settings: one [AgentCard] per agent and the button for an own ACP agent
/// (a preview until M5).
/// {@endtemplate}
class AgentsSettingsSection extends StatelessWidget {
  /// {@macro agents_settings_section}
  const AgentsSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AgentsConfigInhWidget.of(context);
    return ListenableBuilder(
      listenable: scope.agents,
      builder: (context, _) {
        final agents = switch (scope.agents.state) {
          Agents$CompletedState(:final agents) || Agents$ErrorState(:final agents) => agents,
          Agents$InitialState() => const <AgentInfo>[],
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final agent in agents) ...<Widget>[
              AgentCard(key: ValueKey<String>('agent-card-${agent.id}'), agent: agent),
              const SizedBox(height: 12),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  CompactButton(
                    label: Localization.of(context).agentAddCustom,
                    onPressed: scope.showCustomAgentComingSoon,
                  ),
                  const PreviewBadge(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
