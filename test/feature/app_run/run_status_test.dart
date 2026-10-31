import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// [child] with the app's theme and strings; [RunStatus] needs nothing else.
Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: AppTheme.light(),
  locale: locale,
  localizationsDelegates: GeneratedLocalization.localizationsDelegates,
  supportedLocales: Localization.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('RunStatus while building', () {
    testWidgets('an unknown progress is an indeterminate bar under "Building…"', (tester) async {
      await tester.pumpWidget(_app(const RunStatus(run: RunBuilding())));

      expect(find.text('Building…'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(bar.value, isNull);
    });

    testWidgets('in Russian it says "Сборка…"', (tester) async {
      await tester.pumpWidget(
        _app(const RunStatus(run: RunBuilding()), locale: const Locale('ru')),
      );

      expect(find.text('Сборка…'), findsOneWidget);
    });

    testWidgets('a known label and progress are shown as they are', (tester) async {
      await tester.pumpWidget(
        _app(const RunStatus(run: RunBuilding(progress: 0.5, label: 'Xcode build'))),
      );

      expect(find.text('Xcode build'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(bar.value, 0.5);
    });
  });
}
