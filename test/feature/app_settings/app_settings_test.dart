import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/app_close/widgets/app_close_guard.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/initialization/widget/app.dart';
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

  test('wrong-typed fields fall back to their defaults', () {
    final settings = AppSettings.fromJson(const <String, Object?>{
      'themeMode': 3,
      'locale': 7,
      'sidebarVisible': 'yes',
      'rightPaneVisible': 'x',
      'rightPaneWidth': '400',
      'defaultAgentId': 5,
    });
    expect(settings, const AppSettings());
    expect(
      AppSettings.fromJson(const <String, Object?>{'defaultAgentId': ''}).defaultAgentId,
      'claude',
    );
  });

  test('a non-finite pane width falls back to the default', () {
    for (final width in <double>[double.nan, double.infinity, double.negativeInfinity]) {
      expect(
        AppSettings.fromJson(<String, Object?>{'rightPaneWidth': width}).rightPaneWidth,
        AppSettings.defaultRightPaneWidth,
      );
    }
  });

  test('"by window width" survives a JSON round trip', () {
    const settings = AppSettings(sidebarVisible: false);
    expect(settings.rightPaneVisible, isNull);
    expect(AppSettings.fromJson(settings.toJson()).rightPaneVisible, isNull);
    expect(AppSettings.fromJson(settings.toJson()), settings);
  });

  test('copyWith keeps unset fields and resets nullable ones on request', () {
    const settings = AppSettings(locale: Locale('ru'), rightPaneVisible: true, rightPaneWidth: 400);
    expect(settings.copyWith(themeMode: ThemeMode.dark).locale, const Locale('ru'));
    expect(settings.copyWith(themeMode: ThemeMode.dark).rightPaneVisible, isTrue);
    expect(settings.copyWith(resetLocale: true).locale, isNull);
    expect(settings.copyWith(resetRightPaneVisible: true).rightPaneVisible, isNull);
    expect(settings.copyWith(resetLocale: true).rightPaneWidth, 400);
    expect(settings.copyWith(locale: const Locale('en'), resetLocale: true).locale, isNull);
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

    test('a live watch() stream emits after update', () async {
      final emitted = <AppSettings>[];
      final subscription = repository.watch().listen(emitted.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(emitted, <AppSettings>[const AppSettings()]);

      await repository.update(const AppSettings(themeMode: ThemeMode.dark));
      await pumpEventQueue();
      await repository.update(const AppSettings(themeMode: ThemeMode.dark, sidebarVisible: false));
      await pumpEventQueue();

      expect(emitted.map((s) => s.themeMode), <ThemeMode>[
        ThemeMode.system,
        ThemeMode.dark,
        ThemeMode.dark,
      ]);
      expect(emitted.last.sidebarVisible, isFalse);
    });

    test('a row with invalid JSON reads as defaults', () async {
      await dependencies.database
          .into(dependencies.database.appSettingsTable)
          .insert(AppSettingsTableCompanion.insert(key: 'app', value: '{'));
      expect(await repository.watch().first, const AppSettings());
    });
  });

  group('the real App', () {
    setUp(() {
      // window_manager is used by AppCloseGuard; the platform side does not exist in tests.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async => null,
      );
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'), null),
    );

    Future<void> pumpApp(WidgetTester tester, Dependencies dependencies) async {
      useDesktopView(tester);
      await tester.pumpWidget(
        dependencies.inject(child: const AppSettingsConfigWidget(child: App())),
      );
      await tester.pumpAndSettle();
    }

    BuildContext appContext(WidgetTester tester) => tester.element(find.byType(AppCloseGuard));

    testWidgets('dark mode applies once the change is stored', (tester) async {
      final dependencies = testDependencies();
      await pumpApp(tester, dependencies);
      expect(Theme.of(appContext(tester)).brightness, Brightness.light);
      expect(find.text('Skills'), findsOneWidget);

      AppSettingsConfigInhWidget.of(appContext(tester)).controller
          .update((current) => current.copyWith(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();
      expect(Theme.of(appContext(tester)).brightness, Brightness.dark);

      final stored = await tester.runAsync(
        () => AppSettingsRepositoryImpl(database: dependencies.database).watch().first,
      );
      expect(stored!.themeMode, ThemeMode.dark);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('stored dark theme and Russian language apply on start', (tester) async {
      final dependencies = testDependencies();
      await tester.runAsync(
        () =>
            AppSettingsRepositoryImpl(database: dependencies.database)
                .update(const AppSettings(themeMode: ThemeMode.dark, locale: Locale('ru'))),
      );
      await pumpApp(tester, dependencies);

      expect(Theme.of(appContext(tester)).brightness, Brightness.dark);
      expect(find.text('Скиллы'), findsOneWidget);
      expect(find.text('Skills'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('switching the language applies at once', (tester) async {
      final dependencies = testDependencies();
      await pumpApp(tester, dependencies);
      AppSettingsConfigInhWidget.of(appContext(tester)).controller
          .update((current) => current.copyWith(locale: const Locale('ru')));
      await tester.pumpAndSettle();
      expect(find.text('Скиллы'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });
  });
}
