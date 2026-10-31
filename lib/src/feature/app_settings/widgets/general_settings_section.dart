import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/settings_row.dart';

/// {@template general_settings_section}
/// The "General" section of Settings: the app language and whether quitting asks first.
/// {@endtemplate}
class GeneralSettingsSection extends StatelessWidget {
  /// {@macro general_settings_section}
  const GeneralSettingsSection({super.key});

  static const String _system = 'system';

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final controller = AppSettingsConfigInhWidget.of(context).controller;
    return ListenableBuilder(
      listenable: controller,
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
