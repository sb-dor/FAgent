import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/segmented_control.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/settings_row.dart';

/// {@template appearance_settings_section}
/// The "Appearance" section of Settings: the theme and the density of the chat feed.
/// {@endtemplate}
class AppearanceSettingsSection extends StatelessWidget {
  /// {@macro appearance_settings_section}
  const AppearanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final controller = AppSettingsConfigInhWidget.of(context).controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final settings = controller.settings;
        return SettingsCard(
          children: <Widget>[
            SettingsRow(
              label: localization.settingsTheme,
              control: SegmentedControl<ThemeMode>(
                segments: <(ThemeMode, String)>[
                  (ThemeMode.system, localization.settingsThemeSystem),
                  (ThemeMode.light, localization.settingsThemeLight),
                  (ThemeMode.dark, localization.settingsThemeDark),
                ],
                selected: settings.themeMode,
                onChanged: (mode) => controller.update((s) => s.copyWith(themeMode: mode)),
              ),
            ),
            SettingsRow(
              label: localization.settingsDensity,
              hint: localization.settingsDensityHint,
              control: SegmentedControl<FeedDensity>(
                segments: <(FeedDensity, String)>[
                  (FeedDensity.comfortable, localization.settingsDensityComfortable),
                  (FeedDensity.compact, localization.settingsDensityCompact),
                ],
                selected: settings.feedDensity,
                onChanged: (density) => controller.update((s) => s.copyWith(feedDensity: density)),
              ),
            ),
          ],
        );
      },
    );
  }
}
