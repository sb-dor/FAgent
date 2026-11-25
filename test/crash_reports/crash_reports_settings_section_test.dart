import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_code_agent/_core/telemetry/telemetry.dart';
import 'package:flutter_code_agent/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/crash_reports/widgets/crash_reports_config_widget.dart';
import 'package:flutter_code_agent/crash_reports/widgets/crash_reports_settings_section.dart';
import 'package:flutter_code_agent/initialization/models/dependencies.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_crash_reports_repository.dart';
import '../support/test_app.dart';

Future<Dependencies> _pump(
  WidgetTester tester,
  FakeCrashReportsRepository repository, {
  Future<String?> Function(String)? pick,
}) async {
  useDesktopView(tester);
  final dependencies = testDependencies();
  await tester.pumpWidget(
    testApp(
      CrashReportsConfigWidget(
        repository: repository,
        child: Builder(
          builder: (context) {
            if (pick != null) CrashReportsConfigInhWidget.of(context).pickSavePath = pick;
            return const SingleChildScrollView(child: CrashReportsSettingsSection());
          },
        ),
      ),
      dependencies: dependencies,
      withSettings: true,
    ),
  );
  await tester.pumpAndSettle();
  return dependencies;
}

Switch _switch(WidgetTester tester) =>
    tester.widget<Switch>(find.byKey(const ValueKey('crash-reports-switch')));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('the switch is off by default and the note explains what is sent', (tester) async {
    final dependencies = await _pump(tester, FakeCrashReportsRepository());

    expect(_switch(tester).value, isFalse);
    expect(_switch(tester).onChanged, isNotNull);
    expect(
      find.text('Only errors after you turn this on are sent. The log stays on this Mac.'),
      findsOneWidget,
    );
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('without a reporter the switch is disabled and says why', (tester) async {
    final dependencies = await _pump(tester, FakeCrashReportsRepository(configured: false));

    expect(_switch(tester).onChanged, isNull);
    expect(find.text('This build has no crash reporting'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('turning the switch on stores the consent and applies it', (tester) async {
    final repository = FakeCrashReportsRepository();
    final dependencies = await _pump(tester, repository);

    await tester.tap(find.byKey(const ValueKey('crash-reports-switch')));
    await tester.pumpAndSettle();

    final settings = AppSettingsConfigInhWidget.of(
      tester.element(find.byType(CrashReportsSettingsSection)),
    ).controller.settings;
    expect(settings.crashReports, isTrue);
    expect(settings.crashReportsSince, isNotNull);
    expect(_switch(tester).value, isTrue);
    expect(repository.applied.last, (true, settings.crashReportsSince));
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('shows the count and at most 20 recent errors', (tester) async {
    final entries = <OutboxEntry>[for (var i = 0; i < 25; i++) fakeOutboxEntry(i)];
    final dependencies = await _pump(tester, FakeCrashReportsRepository(entries: entries));

    expect(find.text('Recorded errors: 25'), findsOneWidget);
    expect(find.textContaining('StateError: boom'), findsNWidgets(20));
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('Save log archive passes the chosen path to the controller', (tester) async {
    final repository = FakeCrashReportsRepository();
    final dependencies = await _pump(tester, repository, pick: (name) async => '/tmp/chosen.zip');

    await tester.tap(find.byKey(const ValueKey('crash-reports-archive')));
    await tester.pumpAndSettle();

    expect(repository.saved, <String>['/tmp/chosen.zip']);
    expect(find.text('Log archive saved.'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a cancelled dialog saves nothing', (tester) async {
    final repository = FakeCrashReportsRepository();
    final dependencies = await _pump(tester, repository, pick: (name) async => null);

    await tester.tap(find.byKey(const ValueKey('crash-reports-archive')));
    await tester.pumpAndSettle();

    expect(repository.saved, isEmpty);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a failed save shows the error message in a SnackBar', (tester) async {
    final repository = FakeCrashReportsRepository(
      saveError: const FileSystemException('Permission denied', '/locked/log.zip'),
    );
    final dependencies = await _pump(tester, repository, pick: (name) async => '/locked/log.zip');

    await tester.tap(find.byKey(const ValueKey('crash-reports-archive')));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('/locked/log.zip'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });
}
