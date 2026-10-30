import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dependencies backed by an in-memory database; no agent is ever started. A test can pass its own
/// [appRunRepository].
Dependencies testDependencies({
  Duration step = const Duration(milliseconds: 1),
  IAppRunRepository? appRunRepository,
}) {
  final database = AppDatabase(NativeDatabase.memory());
  const environment = ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'});
  return Dependencies()
    ..database = database
    ..shellEnvironment = environment
    ..agentHub = AgentHub(database: database, environment: environment)
    ..devicesRepository = FakeDevicesRepositoryImpl(step: step)
    ..appRunRepository = appRunRepository ?? FakeAppRunRepositoryImpl(step: step)
    ..widgetPickerRepository = FakeWidgetPickerRepositoryImpl(step: step);
}

/// Wraps [child] in the app's localizations, [theme] (light by default) and [dependencies].
///
/// With [withSettings] the app also has the window settings (`AppSettingsConfigWidget`) that the
/// workspace widgets need. They watch the database, so such a test must end with [disposeTestApp].
///
/// [builder] wraps the app's navigator, so what it adds is an ancestor of every route.
Widget testApp(
  Widget child, {
  Dependencies? dependencies,
  Locale locale = const Locale('en'),
  ThemeData? theme,
  TransitionBuilder? builder,
  bool withSettings = false,
}) {
  final app = MaterialApp(
    theme: theme ?? AppTheme.light(),
    builder: builder,
    locale: locale,
    localizationsDelegates: const <LocalizationsDelegate<Object?>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      Localization.delegate,
    ],
    supportedLocales: Localization.supportedLocales,
    home: Scaffold(body: child),
  );
  return (dependencies ?? testDependencies()).inject(
    child: withSettings ? AppSettingsConfigWidget(child: app) : app,
  );
}

/// A desktop-sized test view.
void useDesktopView(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1280, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Unmounts the app so drift's stream subscriptions are cancelled, then lets
/// their zero-length cleanup timers fire (flutter_test fails on timers left
/// after a test). The in-memory database is simply dropped.
Future<void> disposeTestApp(WidgetTester tester, Dependencies dependencies) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
