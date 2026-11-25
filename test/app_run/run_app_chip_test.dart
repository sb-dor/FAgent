import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_code_agent/app_run/controller/devices_controller.dart';
import 'package:flutter_code_agent/app_run/controller/run_controller.dart';
import 'package:flutter_code_agent/app_run/models/device.dart';
import 'package:flutter_code_agent/app_run/widgets/run_app_chip.dart';
import 'package:flutter_code_agent/app_run/widgets/run_header.dart';
import 'package:flutter_code_agent/initialization/models/dependencies.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/test_app.dart';

const Device _macos = Device(
  id: 'macos',
  name: 'macOS',
  platform: DevicePlatform.macos,
  kind: DeviceKind.running,
);

const List<String> _apps = <String>['apps/desktop', 'apps/mobile'];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('RunAppChip', () {
    late Dependencies dependencies;

    setUp(() => dependencies = testDependencies());

    Future<void> pumpHeader(WidgetTester tester, RunViewState state) async {
      useDesktopView(tester);
      await tester.pumpWidget(
        testApp(
          RunHeader(
            state: state,
            devices: const DevicesState.completed(<Device>[_macos]),
            isPreview: false,
            onApp: (_) {},
            onDevice: (_) {},
            onEditArguments: () {},
            onMode: (_) {},
            onAction: (_) {},
            onRetryDevices: () {},
            onOpenFlutterSettings: () {},
            onConfig: (_) {},
            onOpenLaunchJson: () {},
            onConfigMenuOpening: () async {},
          ),
          dependencies: dependencies,
          withSettings: true,
        ),
      );
    }

    Future<void> pumpChip(
      WidgetTester tester, {
      List<String> apps = _apps,
      String appFolder = 'apps/desktop',
      bool locked = false,
      ValueChanged<String>? onSelected,
      Locale locale = const Locale('en'),
    }) async {
      useDesktopView(tester);
      await tester.pumpWidget(
        testApp(
          Center(
            child: RunAppChip(
              apps: apps,
              appFolder: appFolder,
              locked: locked,
              onSelected: onSelected ?? (_) {},
            ),
          ),
          locale: locale,
        ),
      );
    }

    testWidgets('chip shows only for a monorepo', (tester) async {
      await pumpHeader(
        tester,
        const RunViewState(projectId: 1, monorepo: true, apps: _apps, appFolder: 'apps/desktop'),
      );
      expect(find.byType(RunAppChip), findsOneWidget);
      expect(find.text('desktop'), findsOneWidget);

      await pumpHeader(tester, const RunViewState(projectId: 1));
      expect(find.byType(RunAppChip), findsNothing);

      await disposeTestApp(tester, dependencies);
    });

    testWidgets('picking an app calls chooseApp', (tester) async {
      final picked = <String>[];
      await pumpChip(tester, onSelected: picked.add);

      await tester.tap(find.text('desktop'));
      await tester.pumpAndSettle();
      expect(find.text('apps/mobile'), findsOneWidget, reason: 'the menu names the folders');
      await tester.tap(find.text('mobile'));
      await tester.pumpAndSettle();

      expect(picked, <String>['apps/mobile']);
    });

    testWidgets('locked chip is disabled', (tester) async {
      final picked = <String>[];
      await pumpChip(tester, appFolder: 'apps/mobile', locked: true, onSelected: picked.add);

      expect(find.text('mobile'), findsOneWidget);
      await tester.tap(find.text('mobile'));
      await tester.pumpAndSettle();

      expect(find.text('apps/desktop'), findsNothing, reason: 'no menu opens');
      expect(picked, isEmpty);
      final inkWell = tester.widget<InkWell>(
        find.descendant(of: find.byType(RunAppChip), matching: find.byType(InkWell)),
      );
      expect(inkWell.onTap, isNull);
    });

    testWidgets('no Flutter app shows runNoApps', (tester) async {
      await pumpChip(tester, apps: const <String>[], appFolder: '');
      expect(find.text('No Flutter app in apps/'), findsOneWidget);

      await pumpChip(tester, apps: const <String>[], appFolder: '', locale: const Locale('ru'));
      expect(find.text('В apps/ нет Flutter-приложения'), findsOneWidget);
    });
  });
}
