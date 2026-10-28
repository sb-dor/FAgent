import 'package:control/control.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/app_settings/controller/app_settings_controller.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('missing or broken settings fall back to defaults', () {
    for (final json in const <Object?>[
      null,
      'oops',
      <String, Object?>{'themeMode': 'neon', 'rightPaneWidth': 9000},
    ]) {
      final settings = AppSettings.fromJson(json);
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.locale, isNull);
      expect(settings.sidebarVisible, isTrue);
      expect(settings.defaultAgentId, 'claude');
    }
    expect(
      AppSettings.fromJson(const <String, Object?>{'rightPaneWidth': 9000}).rightPaneWidth,
      560,
    );
    expect(AppSettings.fromJson(const <String, Object?>{'rightPaneWidth': 10}).rightPaneWidth, 340);
    expect(AppSettings.fromJson(const <String, Object?>{'locale': 'xx'}).locale, isNull);
  });

  test('settings round-trip through JSON', () {
    const settings = AppSettings(
      themeMode: ThemeMode.dark,
      locale: Locale('ru'),
      sidebarVisible: false,
      rightPaneVisible: true,
      rightPaneWidth: 420,
    );
    expect(AppSettings.fromJson(settings.toJson()), settings);
    expect(AppSettings.fromJson(settings.toJson()).hashCode, settings.hashCode);
  });

  group('repository', () {
    late Dependencies dependencies;
    late AppSettingsRepositoryImpl repository;

    setUp(() {
      dependencies = testDependencies();
      repository = AppSettingsRepositoryImpl(database: dependencies.database);
    });
    tearDown(() => dependencies.database.close());

    test('stores one row and emits updates', () async {
      expect(await repository.watch().first, const AppSettings());

      await repository.update(const AppSettings(themeMode: ThemeMode.dark));
      await repository.update(const AppSettings(themeMode: ThemeMode.dark, rightPaneWidth: 400));

      expect((await repository.watch().first).themeMode, ThemeMode.dark);
      expect((await repository.watch().first).rightPaneWidth, 400);
      final rows = await dependencies.database.select(dependencies.database.appSettingsTable).get();
      expect(rows, hasLength(1));
    });

    test('a row with invalid JSON reads as defaults', () async {
      await dependencies.database
          .into(dependencies.database.appSettingsTable)
          .insert(AppSettingsTableCompanion.insert(key: 'app', value: '{'));
      expect(await repository.watch().first, const AppSettings());
    });
  });

  testWidgets('dark mode applies to the app', (tester) async {
    final dependencies = testDependencies();
    addTearDown(dependencies.database.close);
    late BuildContext inside;
    await tester.pumpWidget(
      dependencies.inject(
        child: AppSettingsConfigWidget(
          child: Builder(
            builder: (context) => StateConsumer<AppSettingsController, AppSettingsState>(
              controller: AppSettingsConfigInhWidget.of(context).controller,
              builder: (context, state, _) => MaterialApp(
                themeMode: AppSettingsConfigInhWidget.of(context).controller.settings.themeMode,
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                home: Builder(
                  builder: (context) {
                    inside = context;
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(Theme.of(inside).brightness, Brightness.light);

    AppSettingsConfigInhWidget.of(inside).controller
        .update((current) => current.copyWith(themeMode: ThemeMode.dark));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(Theme.of(inside).brightness, Brightness.dark);

    await disposeTestApp(tester, dependencies);
  });
}
