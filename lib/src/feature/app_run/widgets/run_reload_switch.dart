import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';

/// {@template run_reload_switch}
/// The switch that makes the app hot reload after every agent turn; it is stored in the settings.
/// {@endtemplate}
class RunReloadSwitch extends StatelessWidget {
  /// {@macro run_reload_switch}
  const RunReloadSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsConfigInhWidget.of(context).controller;
    final style = Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 11);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Row(
        children: <Widget>[
          SizedBox(
            width: 40,
            height: 24,
            child: FittedBox(
              child: Switch(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                value: settings.settings.reloadAfterTurn,
                onChanged: (value) =>
                    settings.update((current) => current.copyWith(reloadAfterTurn: value)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(Localization.of(context).reloadAfterTurn, style: style)),
        ],
      ),
    );
  }
}
