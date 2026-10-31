import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_roles.dart';

/// The settings of an agent a new chat can start with.
enum AgentDefaultRole {
  /// The model.
  model('model', Icons.auto_awesome_outlined),

  /// How much the model thinks.
  effort('effort', Icons.speed),

  /// The permission mode.
  mode('mode', Icons.shield_outlined);

  const AgentDefaultRole(this.fallbackId, this.icon);

  /// The id of the setting when the agent has not told its catalog yet.
  final String fallbackId;

  /// Icon of the chip.
  final IconData icon;

  /// The option of this role among [options], if the agent has one.
  SelectConfigOption? optionIn(List<ConfigOption> options) => switch (this) {
    model => modelOption(options),
    effort => effortOption(options),
    mode => permissionModeOf(options),
  };
}

/// What the user picked in the menu of [AgentDefaults].
final class _Pick {
  const _Pick.value(String this.value);
  const _Pick.reset() : value = null;

  /// The value to store; `null` removes the stored one.
  final String? value;
}

/// {@template agent_defaults}
/// A chip with the value a new chat of [agentId] starts with for [role] (model, effort or mode).
/// Its menu lists the choices of the agent's catalog, never `bypassPermissions`, and stores the
/// pick in `AppSettings.sessionDefaults`.
///
/// The chip shows the name of the stored value, the stored value itself while the catalog cannot
/// name it, or "As the agent has it" when nothing is stored. Before the agent has ever reported its
/// settings the menu says where they come from and only offers to reset a stored value.
/// {@endtemplate}
class AgentDefaults extends StatelessWidget {
  /// {@macro agent_defaults}
  const AgentDefaults({
    required this.agentId,
    required this.role,
    required this.options,
    super.key,
  });

  /// The agent whose defaults these are.
  final String agentId;

  /// Which setting the chip is for.
  final AgentDefaultRole role;

  /// The settings the agent reported on earlier runs; empty before the first chat.
  final List<ConfigOption> options;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final controller = AppSettingsConfigInhWidget.of(context).controller;
    final option = role.optionIn(options);
    final configId = option?.id ?? role.fallbackId;
    final choices = <ConfigChoice>[
      for (final choice in option?.choices ?? const <ConfigChoice>[])
        if (choice.value != bypassPermissionMode) choice,
    ];
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final stored = controller.settings.sessionDefaults[agentId]?[configId];
        final storedName = stored == null
            ? null
            : choices.where((c) => c.value == stored).firstOrNull?.name ?? stored;
        return SelectorChip<_Pick>(
          key: ValueKey<String>('agent-default-$agentId-${role.name}'),
          label: storedName ?? localization.agentDefaultAsAgent,
          icon: role.icon,
          tooltip: option?.name ?? _roleName(localization),
          menuWidth: 320,
          searchable: choices.length > 8,
          sections: <AppMenuSection<_Pick>>[
            if (choices.isEmpty)
              AppMenuSection<_Pick>(
                items: <AppMenuItem<_Pick>>[
                  AppMenuItem<_Pick>(
                    value: const _Pick.reset(),
                    title: localization.agentDefaultNoCatalog,
                    enabled: false,
                  ),
                ],
              )
            else
              AppMenuSection<_Pick>(
                items: <AppMenuItem<_Pick>>[
                  for (final choice in choices)
                    AppMenuItem<_Pick>(
                      value: _Pick.value(choice.value),
                      title: choice.name,
                      subtitle: choice.description,
                      selected: choice.value == stored,
                    ),
                ],
              ),
            if (stored != null)
              AppMenuSection<_Pick>(
                items: <AppMenuItem<_Pick>>[
                  AppMenuItem<_Pick>(
                    value: const _Pick.reset(),
                    title: localization.agentDefaultReset,
                    icon: Icons.restart_alt,
                  ),
                ],
              ),
          ],
          onSelected: (pick) => controller.update((settings) {
            final defaults = <String, Map<String, String>>{
              for (final MapEntry(:key, :value) in settings.sessionDefaults.entries)
                key: <String, String>{...value},
            };
            final mine = defaults.putIfAbsent(agentId, () => <String, String>{});
            final value = pick.value;
            if (value == null) {
              mine.remove(configId);
            } else {
              mine[configId] = value;
            }
            return settings.copyWith(sessionDefaults: defaults);
          }),
        );
      },
    );
  }

  String _roleName(GeneratedLocalization localization) => switch (role) {
    AgentDefaultRole.model => localization.modelLabel,
    AgentDefaultRole.effort => localization.agentEffort,
    AgentDefaultRole.mode => localization.modeLabel,
  };
}
