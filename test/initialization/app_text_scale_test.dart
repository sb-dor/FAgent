import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/app_close/widgets/app_close_guard.dart';
import 'package:flutter_code_agent/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/initialization/widget/app.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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

  Future<double> scaledTen(WidgetTester tester, double systemScale) async {
    tester.platformDispatcher.textScaleFactorTestValue = systemScale;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final dependencies = testDependencies();
    useDesktopView(tester);
    await tester.pumpWidget(
      dependencies.inject(child: const AppSettingsConfigWidget(child: App())),
    );
    await tester.pumpAndSettle();
    final scale = MediaQuery.textScalerOf(tester.element(find.byType(AppCloseGuard))).scale(10);
    await disposeTestApp(tester, dependencies);
    return scale;
  }

  testWidgets('a large system text size is clamped to 1.5x', (tester) async {
    expect(await scaledTen(tester, 2), 15);
  });

  testWidgets('a small system text size is raised to 1x', (tester) async {
    expect(await scaledTen(tester, 0.8), 10);
  });

  testWidgets('a size inside the range is kept', (tester) async {
    expect(await scaledTen(tester, 1.2), closeTo(12, 1e-9));
  });
}
