import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_card.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/compact_button.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_code_agent/src/common/widget/status.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/widgets/agent_defaults.dart';
import 'package:flutter_code_agent/src/feature/agents/widgets/agents_config_widget.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';

/// {@template agent_card}
/// One agent on the Settings screen: its name, version and runtime, where it stands (checking,
/// signed in, needs login, not installed), the action that fits (sign out, sign in, install), the
/// output of a login, and, for an agent that can start chats, the defaults a new chat starts with.
/// {@endtemplate}
class AgentCard extends StatelessWidget {
  /// {@macro agent_card}
  const AgentCard({required this.agent, super.key});

  /// The agent to show.
  final AgentInfo agent;

  /// Login lines shown under the header.
  static const int maxOutputLines = 8;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final scope = AgentsConfigInhWidget.of(context);
    final settings = AppSettingsConfigInhWidget.of(context).controller;
    final details = <String>[?agent.version, ?agent.runtime].join(' · ');
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[settings, scope.actions]),
      builder: (context, _) {
        final output = scope.actions.state.output[agent.id] ?? const <String>[];
        final problem = agent.status == AgentStatus.notInstalled
            ? <String>[?agent.problem, ?agent.hint]
            : const <String>[];
        final bodyParts = <Widget>[
          for (final line in problem)
            Text(
              line,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.muted),
            ),
          if (output.isNotEmpty) _LoginOutput(lines: output),
          if (agent.canStartChats) _Defaults(agent: agent),
        ];
        return AppCard(
          leading: _Logo(agentId: agent.id),
          title: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(agent.name),
              if (settings.settings.defaultAgentId == agent.id)
                StatusPill(label: localization.agentDefaultBadge, tone: AppStatusTone.active),
              if (agent.isPreview) const PreviewBadge(),
            ],
          ),
          subtitle: details.isEmpty
              ? null
              : Text(
                  details,
                  style: AppText.mono(context, size: 11).copyWith(color: colors.muted),
                ),
          trailing: <Widget>[
            _StatusLabel(agent: agent),
            ..._actions(context, localization, scope),
          ],
          body: bodyParts.isEmpty
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final (index, part) in bodyParts.indexed) ...<Widget>[
                      if (index > 0) const SizedBox(height: 12),
                      part,
                    ],
                  ],
                ),
        );
      },
    );
  }

  List<Widget> _actions(
    BuildContext context,
    GeneratedLocalization localization,
    AgentsConfigWidgetState scope,
  ) => switch (agent.status) {
    AgentStatus.ready => <Widget>[
      CompactButton(
        label: localization.agentSignOut,
        onPressed: () => scope.actions.logout(agent.id),
      ),
    ],
    AgentStatus.needsLogin when agent.loginMethods.length == 1 => <Widget>[
      CompactButton(
        label: _methodLabel(localization, agent.loginMethods.single),
        onPressed: () => scope.actions.login(agent.id, agent.loginMethods.single),
      ),
    ],
    AgentStatus.needsLogin when agent.loginMethods.isNotEmpty => <Widget>[
      SelectorChip<String>(
        label: localization.agentSignIn,
        sections: <AppMenuSection<String>>[
          AppMenuSection<String>(
            items: <AppMenuItem<String>>[
              for (final method in agent.loginMethods)
                AppMenuItem<String>(value: method, title: _methodLabel(localization, method)),
            ],
          ),
        ],
        onSelected: (method) => scope.actions.login(agent.id, method),
      ),
    ],
    AgentStatus.notInstalled => <Widget>[
      CompactButton(
        label: localization.agentInstall,
        primary: true,
        onPressed: () => scope.actions.install(agent.id),
      ),
    ],
    _ => const <Widget>[],
  };

  static String _methodLabel(GeneratedLocalization localization, String method) => switch (method) {
    'claude-ai-login' => localization.agentLoginClaudeAi,
    'console-login' => localization.agentLoginConsole,
    'google' => localization.agentLoginGoogle,
    _ => method,
  };
}

class _Logo extends StatelessWidget {
  const _Logo({required this.agentId});

  final String agentId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final icon = switch (agentId) {
      'claude' => Icons.auto_awesome,
      'codex' => Icons.terminal,
      'gemini' => Icons.diamond_outlined,
      _ => Icons.smart_toy_outlined,
    };
    return SizedBox.square(
      dimension: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(color: colors.border),
        ),
        child: Icon(icon, size: 18, color: colors.text),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.agent});

  final AgentInfo agent;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final account = agent.account;
    final (label, tone) = switch (agent.status) {
      AgentStatus.checking => (localization.agentStatusChecking, AppStatusTone.none),
      AgentStatus.ready => (
        account == null || account.isEmpty
            ? localization.agentStatusReady
            : localization.agentStatusReadyAccount(account),
        AppStatusTone.ok,
      ),
      AgentStatus.needsLogin => (localization.agentStatusNeedsLogin, AppStatusTone.warn),
      AgentStatus.notInstalled => (localization.agentStatusNotInstalled, AppStatusTone.none),
      AgentStatus.installing => (localization.agentStatusInstalling, AppStatusTone.active),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: StatusPill(label: label, tone: tone),
    );
  }
}

/// The last lines of the running or finished login, as a terminal would show them.
class _LoginOutput extends StatelessWidget {
  const _LoginOutput({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shown = lines.sublist(math.max(0, lines.length - AgentCard.maxOutputLines));
    final style = AppText.mono(context, size: 11);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[for (final line in shown) Text(line, style: style)],
          ),
        ),
      ),
    );
  }
}

/// Model, effort and mode a new chat of the agent starts with, and a way to its own settings.
class _Defaults extends StatelessWidget {
  const _Defaults({required this.agent});

  final AgentInfo agent;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final scope = AgentsConfigInhWidget.of(context);
    return KeyValueGrid(
      rows: <(String, Widget)>[
        (
          localization.agentDefaultModel,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              AgentDefaults(
                agentId: agent.id,
                role: AgentDefaultRole.model,
                options: agent.options,
              ),
              AgentDefaults(
                agentId: agent.id,
                role: AgentDefaultRole.effort,
                options: agent.options,
              ),
            ],
          ),
        ),
        (
          localization.agentDefaultMode,
          AgentDefaults(agentId: agent.id, role: AgentDefaultRole.mode, options: agent.options),
        ),
        if (agent.id == 'claude')
          (
            localization.agentClaudeSettings,
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  '${localization.agentClaudeSettingsNote} — ',
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.muted),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  onTap: () => scope.actions.openSettings(agent.id),
                  child: Text(
                    localization.agentOpen,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.accent),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
