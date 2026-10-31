import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_code_agent/src/feature/agents/widgets/agents_config_widget.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/settings_row.dart';

/// {@template general_settings_section}
/// The "General" section of Settings: the app language, the agent a new chat starts with and
/// whether quitting asks first.
/// {@endtemplate}
class GeneralSettingsSection extends StatelessWidget {
  /// {@macro general_settings_section}
  const GeneralSettingsSection({super.key});

  static const String _system = 'system';

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final controller = AppSettingsConfigInhWidget.of(context).controller;
    final agents = AgentsConfigInhWidget.of(context).agents;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[controller, agents]),
      builder: (context, _) {
        final settings = controller.settings;
        final current = settings.locale?.languageCode ?? _system;
        final names = <String, String>{
          _system: localization.settingsLanguageSystem,
          'en': localization.settingsLanguageEnglish,
          'ru': localization.settingsLanguageRussian,
        };
        return SettingsCard(
          children: <Widget>[
            SettingsRow(
              label: localization.settingsLanguage,
              control: SelectorChip<String>(
                label: names[current] ?? names[_system]!,
                menuWidth: 200,
                sections: <AppMenuSection<String>>[
                  AppMenuSection<String>(
                    items: <AppMenuItem<String>>[
                      for (final MapEntry(:key, :value) in names.entries)
                        AppMenuItem<String>(value: key, title: value, selected: key == current),
                    ],
                  ),
                ],
                onSelected: (code) => controller.update(
                  (s) => code == _system
                      ? s.copyWith(resetLocale: true)
                      : s.copyWith(locale: Locale(code)),
                ),
              ),
            ),
            SettingsRow(
              label: localization.settingsDefaultAgent,
              hint: localization.settingsDefaultAgentHint,
              control: SelectorChip<String>(
                label:
                    agents.agents
                        .where((agent) => agent.id == settings.defaultAgentId)
                        .firstOrNull
                        ?.name ??
                    settings.defaultAgentId,
                icon: Icons.smart_toy_outlined,
                menuWidth: 240,
                sections: <AppMenuSection<String>>[
                  AppMenuSection<String>(
                    items: <AppMenuItem<String>>[
                      for (final agent in agents.agents)
                        AppMenuItem<String>(
                          value: agent.id,
                          title: agent.name,
                          selected: agent.id == settings.defaultAgentId,
                          enabled: agent.canStartChats,
                          badge: agent.canStartChats ? null : const PreviewBadge(),
                        ),
                    ],
                  ),
                ],
                onSelected: (id) => controller.update((s) => s.copyWith(defaultAgentId: id)),
              ),
            ),
            SettingsRow(
              label: localization.settingsQuit,
              hint: localization.settingsQuitHint,
              control: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    localization.settingsQuitAsk,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: context.colors.muted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: settings.askBeforeQuit,
                    onChanged: (value) =>
                        controller.update((s) => s.copyWith(askBeforeQuit: value)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
