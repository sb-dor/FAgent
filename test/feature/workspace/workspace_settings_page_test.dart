import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/app_settings/controller/app_settings_controller.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/settings_row.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

WorkspaceConfigWidgetState _workspace(WidgetTester tester) =>
    WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));

AppSettingsController _settings(WidgetTester tester) => _workspace(tester).settingsController;

/// Lets drift's real-async work finish, then rebuilds.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 100));
}

Finder _pageContent() => find.byKey(const ValueKey<String>('page-content'));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;

  Future<void> openSettings(
    WidgetTester tester,
    String section, {
    Locale locale = const Locale('en'),
    bool dark = false,
    Size size = const Size(1280, 800),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    dependencies = testDependencies();
    await tester.pumpWidget(
      testApp(
        const WorkspaceConfigWidget(),
        dependencies: dependencies,
        withSettings: true,
        locale: locale,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
      ),
    );
    await _settle(tester);
    await tester.pumpAndSettle();
    _workspace(tester).dataController.openView(WorkspaceView.settings, section: section);
    await tester.pump();
    await _settle(tester);
    await tester.pumpAndSettle();
  }

  group('general', () {
    testWidgets('language menu switches to Russian', (tester) async {
      await openSettings(tester, 'general', locale: const Locale('ru'));
      expect(find.descendant(of: _pageContent(), matching: find.text('Общие')), findsOneWidget);
      expect(_settings(tester).settings.locale, isNull);

      await tester.tap(find.text('Системный'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Русский').last);
      await tester.pumpAndSettle();
      await _settle(tester);

      expect(_settings(tester).settings.locale, const Locale('ru'));
      expect(find.descendant(of: _pageContent(), matching: find.text('Общие')), findsOneWidget);
      expect(find.text('Русский'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('language menu resets to the system language', (tester) async {
      await openSettings(tester, 'general');
      _settings(tester).update((s) => s.copyWith(locale: const Locale('ru')));
      await _settle(tester);
      expect(find.text('Русский'), findsOneWidget);

      await tester.tap(find.text('Русский'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('System').last);
      await tester.pumpAndSettle();
      await _settle(tester);

      expect(_settings(tester).settings.locale, isNull);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('ask before quit switch', (tester) async {
      await openSettings(tester, 'general');
      expect(_settings(tester).settings.askBeforeQuit, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      await _settle(tester);

      expect(_settings(tester).settings.askBeforeQuit, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await disposeTestApp(tester, dependencies);
    });
  });

  testWidgets('appearance: theme and density', (tester) async {
    await openSettings(tester, 'appearance', locale: const Locale('ru'));
    expect(_settings(tester).settings.themeMode, ThemeMode.system);
    expect(_settings(tester).settings.feedDensity, FeedDensity.comfortable);

    await tester.tap(find.text('Тёмная'));
    await tester.pump();
    await _settle(tester);
    await tester.tap(find.text('Компактная'));
    await tester.pump();
    await _settle(tester);

    expect(_settings(tester).settings.themeMode, ThemeMode.dark);
    expect(_settings(tester).settings.feedDensity, FeedDensity.compact);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('shortcuts lists every binding', (tester) async {
    await openSettings(tester, 'shortcuts');
    for (final keys in <String>[
      '⌘N',
      '⌘K',
      r'⌘\',
      '⌘J',
      '⌘,',
      '⌘R',
      '⇧⌘R',
      '⇧Tab',
      '↵ / Esc',
      'Esc',
    ]) {
      expect(find.text(keys), findsOneWidget, reason: keys);
    }
    expect(find.text('Answer the permission card'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('agents shows its subtitle above the cards', (tester) async {
    await openSettings(tester, 'agents');
    expect(find.textContaining('Agent Client Protocol'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  group('SettingsRow', () {
    Future<void> pumpRow(WidgetTester tester, double width) => tester.pumpWidget(
      testApp(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: const SettingsRow(
              label: 'Label',
              hint: 'Hint',
              control: SizedBox(key: ValueKey<String>('control'), width: 100, height: 20),
            ),
          ),
        ),
      ),
    );

    testWidgets('puts the control right of the label from 480 px', (tester) async {
      await pumpRow(tester, 480);
      final label = tester.getTopLeft(find.text('Label'));
      final control = tester.getTopLeft(find.byKey(const ValueKey<String>('control')));
      expect(control.dx, greaterThan(label.dx));
      expect(tester.getCenter(find.byKey(const ValueKey<String>('control'))).dy, lessThan(60));
      expect(tester.takeException(), isNull);
    });

    testWidgets('puts the control under the label below 480 px', (tester) async {
      await pumpRow(tester, 479);
      final hint = tester.getBottomLeft(find.text('Hint'));
      final control = tester.getTopLeft(find.byKey(const ValueKey<String>('control')));
      expect(control.dy, greaterThanOrEqualTo(hint.dy));
      expect(control.dx, tester.getTopLeft(find.text('Label')).dx);
      expect(tester.takeException(), isNull);
    });
  });

  group('layout', () {
    for (final section in const <String>['general', 'appearance', 'shortcuts']) {
      for (final size in const <Size>[Size(900, 600), Size(1280, 800)]) {
        for (final locale in const <Locale>[Locale('en'), Locale('ru')]) {
          for (final dark in const <bool>[false, true]) {
            testWidgets(
              '$section fits ${size.width.toInt()}×${size.height.toInt()} in '
              '${locale.languageCode}, ${dark ? 'dark' : 'light'}',
              (tester) async {
                await openSettings(tester, section, locale: locale, dark: dark, size: size);
                expect(_pageContent(), findsOneWidget);
                expect(tester.takeException(), isNull);
                await disposeTestApp(tester, dependencies);
              },
            );
          }
        }
      }
    }
  });
}
