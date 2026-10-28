import 'package:control/control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/app_close/widgets/app_close_guard.dart';
import 'package:flutter_code_agent/src/feature/app_settings/controller/app_settings_controller.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/hub_notices/widgets/hub_notices_listener.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// {@template app}
/// App widgets.
/// {@endtemplate}
class App extends StatefulWidget {
  /// {@macro app}
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final Key builderKey = GlobalKey(); // Disable recreate widgets tree

  late final _settings = AppSettingsConfigInhWidget.of(context).controller;

  @override
  Widget build(BuildContext context) => StateConsumer<AppSettingsController, AppSettingsState>(
    controller: _settings,
    builder: (context, state, _) => _buildApp(),
  );

  Widget _buildApp() => MaterialApp(
    onGenerateTitle: (context) => Localization.of(context).appTitle,
    debugShowCheckedModeBanner: false,

    // Localizations
    localizationsDelegates: const <LocalizationsDelegate<Object?>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      Localization.delegate,
    ],
    supportedLocales: Localization.supportedLocales,
    locale: _settings.settings.locale,

    // Theme
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: _settings.settings.themeMode,

    home: const AppCloseGuard(child: HubNoticesListener(child: WorkspaceConfigWidget())),
    builder: (context, child) => MediaQuery(
      key: builderKey,
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}
