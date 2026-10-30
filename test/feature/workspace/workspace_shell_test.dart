import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/feature/app_settings/controller/app_settings_controller.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_chat_area.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_page_scaffold.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_right_pane.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_sidebar.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void useWindow(WidgetTester tester, double width, double height) {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Lets drift's real-async work finish, then rebuilds.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 100));
}

WorkspaceDataController dataOf(WidgetTester tester) =>
    WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget))).dataController;

AppSettingsController settingsOf(WidgetTester tester) =>
    AppSettingsConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget))).controller;

Future<void> pressWithMeta(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
  await settle(tester);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;

  setUp(() => dependencies = testDependencies());

  Future<void> pumpShell(WidgetTester tester, {AppSettings? stored, bool withChat = false}) async {
    await tester.runAsync(() async {
      if (stored != null) {
        await AppSettingsRepositoryImpl(database: dependencies.database).update(stored);
      }
      if (withChat) {
        final database = dependencies.database;
        final project = await database
            .into(database.projectsTable)
            .insert(ProjectsTableCompanion.insert(path: '/work/avera-hotel', name: 'avera-hotel'));
        await database
            .into(database.sessionsTable)
            .insert(
              SessionsTableCompanion.insert(
                projectId: project,
                agentId: 'claude',
                title: const Value<String>('Add a booking screen'),
              ),
            );
      }
    });
    await tester.pumpWidget(
      testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
    );
    await settle(tester);
    await tester.pumpAndSettle();
  }

  /// Opens the seeded chat (which selects its project); the composer's cursor never settles, so
  /// pump by hand.
  Future<void> openChat(WidgetTester tester) async {
    await tester.tap(find.text('Add a booking screen'));
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }
  }

  group('window layout', () {
    testWidgets('1280×800 shows sidebar, chat and the right pane', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester);

      expect(find.byType(WorkspaceSidebar), findsOneWidget);
      expect(find.byType(WorkspaceRightPane), findsOneWidget);
      expect(tester.getSize(find.byType(WorkspaceSidebar)).width, 236);
      expect(tester.getSize(find.byType(WorkspaceRightPane)).width, 380);
      expect(find.byTooltip('Show or hide the sidebar'), findsOneWidget);
      expect(find.byTooltip('Show or hide the side panel'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('900×600 fits with a chat open, the widest stored pane and the sidebar', (
      tester,
    ) async {
      useWindow(tester, 900, 600);
      await pumpShell(
        tester,
        stored: const AppSettings(rightPaneVisible: true, rightPaneWidth: 560),
        withChat: true,
      );
      await openChat(tester);

      expect(find.byType(WorkspaceSidebar), findsOneWidget);
      expect(find.byType(WorkspaceRightPane), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.getSize(find.byType(WorkspaceChatArea)).width, greaterThanOrEqualTo(320));
      expect(tester.getSize(find.byType(WorkspaceRightPane)).width, greaterThanOrEqualTo(340));
      expect(tester.takeException(), isNull);
      // The window only limits what is shown; the preference stays.
      expect(settingsOf(tester).settings.rightPaneWidth, 560);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('below 1100 px the right pane starts closed', (tester) async {
      useWindow(tester, 1000, 700);
      await pumpShell(tester);

      expect(find.byType(WorkspaceSidebar), findsOneWidget);
      expect(find.byType(WorkspaceRightPane), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the title bar names the chat and its project', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester, withChat: true);
      expect(find.text('Flutter Code Agent'), findsOneWidget);

      await openChat(tester);
      expect(find.text('Add a booking screen · avera-hotel'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the right pane paints surfaceAlt; Changes is empty and Run asks for a project', (
      tester,
    ) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester);

      final paint = tester.widget<DecoratedBox>(
        find
            .descendant(of: find.byType(WorkspaceRightPane), matching: find.byType(DecoratedBox))
            .first,
      );
      expect((paint.decoration as BoxDecoration).color, AppColors.light.surfaceAlt);
      expect(find.text('No changes yet'), findsOneWidget);
      await tester.tap(find.text('Run'));
      await tester.pump();
      expect(find.text('Select a project to run its app'), findsOneWidget);
      expect(find.textContaining('UI stage'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the right pane switches between its tabs', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester);
      expect(find.text('Changes'), findsWidgets);

      await tester.tap(find.text('Plan'));
      await tester.pump();
      expect(dataOf(tester).paneTab, RightPaneTab.plan);
      await tester.tap(find.text('Run'));
      await tester.pump();
      expect(dataOf(tester).paneTab, RightPaneTab.run);
      await disposeTestApp(tester, dependencies);
    });
  });

  group('panel toggles', () {
    testWidgets('the title bar buttons toggle the panels and save the choice', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester);

      await tester.tap(find.byTooltip('Show or hide the sidebar'));
      await settle(tester);
      await tester.tap(find.byTooltip('Show or hide the side panel'));
      await settle(tester);

      expect(find.byType(WorkspaceSidebar), findsNothing);
      expect(find.byType(WorkspaceRightPane), findsNothing);
      expect(settingsOf(tester).settings.sidebarVisible, isFalse);
      expect(settingsOf(tester).settings.rightPaneVisible, isFalse);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets(r'⌘\ and ⌘J toggle the panels and are saved', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester);

      await pressWithMeta(tester, LogicalKeyboardKey.backslash);
      await pressWithMeta(tester, LogicalKeyboardKey.keyJ);

      expect(find.byType(WorkspaceSidebar), findsNothing);
      expect(find.byType(WorkspaceRightPane), findsNothing);
      expect(settingsOf(tester).settings.sidebarVisible, isFalse);
      expect(settingsOf(tester).settings.rightPaneVisible, isFalse);

      await pressWithMeta(tester, LogicalKeyboardKey.backslash);
      await pressWithMeta(tester, LogicalKeyboardKey.keyJ);
      expect(find.byType(WorkspaceSidebar), findsOneWidget);
      expect(find.byType(WorkspaceRightPane), findsOneWidget);
      expect(settingsOf(tester).settings.sidebarVisible, isTrue);
      expect(settingsOf(tester).settings.rightPaneVisible, isTrue);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('⌘J on a narrow window opens the pane that was closed by width', (tester) async {
      useWindow(tester, 1000, 700);
      await pumpShell(tester);
      expect(find.byType(WorkspaceRightPane), findsNothing);

      await pressWithMeta(tester, LogicalKeyboardKey.keyJ);
      expect(find.byType(WorkspaceRightPane), findsOneWidget);
      expect(settingsOf(tester).settings.rightPaneVisible, isTrue);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the shortcuts work while a text field has focus', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester, withChat: true);
      await openChat(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>(),
        isNotNull,
      );

      await pressWithMeta(tester, LogicalKeyboardKey.backslash);
      await pressWithMeta(tester, LogicalKeyboardKey.keyJ);

      expect(find.byType(WorkspaceSidebar), findsNothing);
      expect(find.byType(WorkspaceRightPane), findsNothing);
      expect(settingsOf(tester).settings.sidebarVisible, isFalse);
      expect(settingsOf(tester).settings.rightPaneVisible, isFalse);
      await disposeTestApp(tester, dependencies);
    });
  });

  group('right pane resize', () {
    final handle = find.byKey(const ValueKey<String>('right-pane-resize-handle'));

    testWidgets('dragging the pane edge clamps 340–560 and saves the width', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester);

      await tester.drag(handle, const Offset(-500, 0));
      await settle(tester);
      expect(tester.getSize(find.byType(WorkspaceRightPane)).width, 560);
      expect(settingsOf(tester).settings.rightPaneWidth, 560);

      await tester.drag(handle, const Offset(500, 0));
      await settle(tester);
      expect(tester.getSize(find.byType(WorkspaceRightPane)).width, 340);
      expect(settingsOf(tester).settings.rightPaneWidth, 340);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the pane follows the finger and writes to settings only at the end', (
      tester,
    ) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester);

      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(-60, 0));
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      final live = tester.getSize(find.byType(WorkspaceRightPane)).width;
      expect(live, greaterThan(380));
      expect(live, lessThan(560));
      expect(settingsOf(tester).settings.rightPaneWidth, 380);

      await gesture.up();
      await settle(tester);
      expect(settingsOf(tester).settings.rightPaneWidth, live);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('dragging wider at 900 px stops where the chat would drop below 320', (
      tester,
    ) async {
      useWindow(tester, 900, 600);
      await pumpShell(tester, stored: const AppSettings(rightPaneVisible: true), withChat: true);
      await openChat(tester);

      await tester.drag(handle, const Offset(-400, 0));
      await settle(tester);
      expect(tester.getSize(find.byType(WorkspaceChatArea)).width, 320);
      expect(tester.getSize(find.byType(WorkspaceRightPane)).width, 343);
      expect(settingsOf(tester).settings.rightPaneWidth, 343);
      expect(tester.takeException(), isNull);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a stored width is used', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester, stored: const AppSettings(rightPaneWidth: 450));
      expect(tester.getSize(find.byType(WorkspaceRightPane)).width, 450);
      await disposeTestApp(tester, dependencies);
    });
  });

  group('screens', () {
    testWidgets('⌘, opens Settings and Esc returns to the same chat', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester, withChat: true);
      await openChat(tester);
      final sessionId = dataOf(tester).sessionId;
      expect(sessionId, isNotNull);
      await tester.enterText(find.byType(TextField), 'half-written prompt');
      await tester.pump();

      await pressWithMeta(tester, LogicalKeyboardKey.comma);
      expect(dataOf(tester).view, WorkspaceView.settings);
      expect(find.byType(WorkspaceSidebar), findsNothing);
      expect(find.byType(WorkspaceRightPane), findsNothing);
      expect(find.byTooltip('Show or hide the side panel'), findsNothing);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Back to chat'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(dataOf(tester).view, WorkspaceView.chat);
      expect(dataOf(tester).sessionId, sessionId);
      expect(find.byType(WorkspaceSidebar), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('half-written prompt'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('Esc in the chat does nothing', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(dataOf(tester).view, WorkspaceView.chat);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('Esc with a menu open keeps Settings open', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester);
      dataOf(tester).openView(WorkspaceView.settings);
      await tester.pump();

      showAppMenu<String>(
        context: tester.element(find.byType(WorkspacePageScaffold)),
        anchor: const Rect.fromLTWH(400, 200, 100, 30),
        sections: const <AppMenuSection<String>>[
          AppMenuSection<String>(
            items: <AppMenuItem<String>>[AppMenuItem<String>(value: 'a', title: 'Menu row')],
          ),
        ],
      ).ignore();
      await tester.pumpAndSettle();
      expect(find.text('Menu row'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Menu row'), findsNothing);
      expect(dataOf(tester).view, WorkspaceView.settings);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(dataOf(tester).view, WorkspaceView.chat);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the back button returns to the chat', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester);
      dataOf(tester).openView(WorkspaceView.skills);
      await tester.pump();
      expect(find.text('Skills and rules'), findsOneWidget);

      await tester.tap(find.text('Back to chat'));
      await tester.pump();
      expect(dataOf(tester).view, WorkspaceView.chat);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('settings sections switch and show their placeholder', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester);
      dataOf(tester).openView(WorkspaceView.settings);
      await tester.pump();

      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.textContaining('UI stage'), findsNothing);
      await tester.tap(find.text('Agents'));
      await tester.pump();
      expect(dataOf(tester).section, 'agents');
      expect(find.text('Coming in M5'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);

      await tester.tap(find.text('Flutter'));
      await tester.pump();
      expect(find.text('Coming in M2'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the skills page has Skills and Rules sections', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester);
      dataOf(tester).openView(WorkspaceView.skills);
      await tester.pump();

      expect(find.text('Coming in M3'), findsOneWidget);
      await tester.tap(find.text('Rules'));
      await tester.pump();
      expect(dataOf(tester).section, 'rules');
      expect(find.text('Coming in M3'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the settings page keeps a 220 px navigation on a wide window', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester);
      dataOf(tester).openView(WorkspaceView.settings);
      await tester.pump();

      final nav = find.byKey(const ValueKey<String>('page-navigation'));
      expect(tester.getSize(nav).width, 220);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the settings page narrows its navigation under 1100 px', (tester) async {
      useWindow(tester, 1000, 700);
      await pumpShell(tester);
      dataOf(tester).openView(WorkspaceView.settings);
      await tester.pump();

      final nav = find.byKey(const ValueKey<String>('page-navigation'));
      expect(tester.getSize(nav).width, 56);
      expect(find.byTooltip('Agents'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the page content is a centered column of at most 640 px', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpShell(tester);
      dataOf(tester).openView(WorkspaceView.settings);
      await tester.pump();

      final column = find.byKey(const ValueKey<String>('page-content'));
      expect(tester.getSize(column).width, 640);
      // Free space right of the 220 px navigation, split evenly around the column.
      expect(tester.getCenter(column).dx, closeTo(220 + 1 + (1280 - 221) / 2, 1));
      await disposeTestApp(tester, dependencies);
    });
  });

  group('WorkspaceDataController screens', () {
    test('openView, section and backToChat', () {
      final controller = WorkspaceDataController();
      addTearDown(controller.dispose);
      var notified = 0;
      controller.addListener(() => notified++);

      expect(controller.view, WorkspaceView.chat);
      expect(controller.section, isNull);
      controller.openView(WorkspaceView.settings, section: 'mcp');
      expect((controller.view, controller.section), (WorkspaceView.settings, 'mcp'));
      controller.openView(WorkspaceView.settings, section: 'mcp');
      expect(notified, 1);

      controller.backToChat();
      expect((controller.view, controller.section), (WorkspaceView.chat, null));
      controller.backToChat();
      expect(notified, 2);
    });

    test('selecting a pane tab', () {
      final controller = WorkspaceDataController();
      addTearDown(controller.dispose);
      expect(controller.paneTab, RightPaneTab.changes);
      controller.selectPaneTab(RightPaneTab.run);
      expect(controller.paneTab, RightPaneTab.run);
    });

    test('screens do not touch the chat selection', () {
      final controller = WorkspaceDataController()
        ..selectProject(1)
        ..selectSession(2)
        ..openView(WorkspaceView.skills);
      addTearDown(controller.dispose);
      controller.backToChat();
      expect((controller.projectId, controller.sessionId), (1, 2));
    });
  });
}
