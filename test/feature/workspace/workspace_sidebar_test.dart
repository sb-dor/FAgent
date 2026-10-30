import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/widget/status.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_chat_tile.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_sidebar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

/// Lets drift's real-async work finish, then rebuilds.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 100));
}

WorkspaceConfigWidgetState scopeOf(WidgetTester tester) =>
    tester.state<WorkspaceConfigWidgetState>(find.byType(WorkspaceConfigWidget));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late AppDatabase database;

  setUp(() {
    dependencies = testDependencies();
    database = dependencies.database;
  });

  void useWindow(WidgetTester tester, double width, double height) {
    tester.view
      ..physicalSize = Size(width, height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Inserts a project and returns its id.
  Future<int> addProject(String name) => database
      .into(database.projectsTable)
      .insert(ProjectsTableCompanion.insert(path: '/work/$name', name: name));

  /// Inserts a chat updated [minutes] after midnight and returns its id.
  Future<int> addChat(int projectId, String title, {int minutes = 0}) => database
      .into(database.sessionsTable)
      .insert(
        SessionsTableCompanion.insert(
          projectId: projectId,
          agentId: 'claude',
          title: Value<String>(title),
          updatedAt: Value<DateTime>(DateTime(2026, 10, 28).add(Duration(minutes: minutes))),
        ),
      );

  Future<void> pumpSidebar(WidgetTester tester) async {
    await tester.pumpWidget(
      testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
    );
    await settle(tester);
    await tester.pumpAndSettle();
  }

  Future<void> pressWithMeta(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await settle(tester);
  }

  test('status tones follow the session status', () {
    const expected = <SessionStatus, AppStatusTone>{
      SessionStatus.cold: AppStatusTone.none,
      SessionStatus.starting: AppStatusTone.active,
      SessionStatus.loading: AppStatusTone.active,
      SessionStatus.creating: AppStatusTone.active,
      SessionStatus.idle: AppStatusTone.none,
      SessionStatus.running: AppStatusTone.active,
      SessionStatus.awaitingPermission: AppStatusTone.warn,
      SessionStatus.cancelling: AppStatusTone.active,
      SessionStatus.setupFailed: AppStatusTone.danger,
      SessionStatus.needsAuth: AppStatusTone.danger,
      SessionStatus.error: AppStatusTone.danger,
      SessionStatus.disposed: AppStatusTone.none,
    };
    expect(expected.keys.toSet(), SessionStatus.values.toSet());
    for (final entry in expected.entries) {
      expect(statusTone(entry.key), entry.value, reason: '${entry.key}');
    }
  });

  group('groups', () {
    testWidgets('chats are grouped under their projects', (tester) async {
      useWindow(tester, 1280, 800);
      await tester.runAsync(() async {
        final avera = await addProject('avera-hotel');
        final shop = await addProject('shop_app');
        await addChat(avera, 'Booking screen', minutes: 10);
        await addChat(avera, 'Stripe payment', minutes: 20);
        await addChat(shop, 'Dark theme', minutes: 5);
        await addChat(shop, 'Push notifications', minutes: 30);
      });
      await pumpSidebar(tester);

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      // Groups: the project with the most recent chat first. Chats: most recent first.
      final order = <String>[
        'shop_app',
        'Push notifications',
        'Dark theme',
        'avera-hotel',
        'Stripe payment',
        'Booking screen',
      ];
      for (var i = 1; i < order.length; i++) {
        expect(
          top(order[i]),
          greaterThan(top(order[i - 1])),
          reason: '${order[i]} after ${order[i - 1]}',
        );
      }
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a project without chats still shows, with a hint', (tester) async {
      useWindow(tester, 1280, 800);
      await tester.runAsync(() async {
        final avera = await addProject('avera-hotel');
        await addChat(avera, 'Booking screen');
        await addProject('empty-one');
      });
      await pumpSidebar(tester);

      expect(find.text('empty-one'), findsOneWidget);
      expect(find.text('No chats yet'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('empty-one')).dy,
        greaterThan(tester.getTopLeft(find.text('Booking screen')).dy),
      );
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('collapsing a project hides its chats', (tester) async {
      useWindow(tester, 1280, 800);
      await tester.runAsync(() async {
        final avera = await addProject('avera-hotel');
        final shop = await addProject('shop_app');
        await addChat(avera, 'Booking screen');
        await addChat(shop, 'Dark theme');
      });
      await pumpSidebar(tester);
      expect(find.text('Booking screen'), findsOneWidget);

      await tester.tap(find.text('avera-hotel'));
      await tester.pump();
      expect(find.text('Booking screen'), findsNothing);
      expect(find.text('Dark theme'), findsOneWidget);

      await tester.tap(find.text('avera-hotel'));
      await tester.pump();
      expect(find.text('Booking screen'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets(r'a collapsed project stays collapsed after hiding the sidebar with ⌘\', (
      tester,
    ) async {
      useWindow(tester, 1280, 800);
      await tester.runAsync(() async {
        final avera = await addProject('avera-hotel');
        await addChat(avera, 'Booking screen');
      });
      await pumpSidebar(tester);

      await tester.tap(find.text('avera-hotel'));
      await tester.pump();
      expect(find.text('Booking screen'), findsNothing);

      await pressWithMeta(tester, LogicalKeyboardKey.backslash);
      expect(find.byType(WorkspaceSidebar), findsNothing);
      await pressWithMeta(tester, LogicalKeyboardKey.backslash);
      expect(find.byType(WorkspaceSidebar), findsOneWidget);

      expect(find.text('avera-hotel'), findsOneWidget);
      expect(find.text('Booking screen'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('picking a chat selects it with its project', (tester) async {
      useWindow(tester, 1280, 800);
      late int shop;
      late int chat;
      await tester.runAsync(() async {
        final avera = await addProject('avera-hotel');
        shop = await addProject('shop_app');
        await addChat(avera, 'Booking screen');
        chat = await addChat(shop, 'Dark theme');
      });
      await pumpSidebar(tester);

      await tester.tap(find.text('Dark theme'));
      for (var i = 0; i < 5; i++) {
        await settle(tester);
      }
      expect(scopeOf(tester).dataController.projectId, shop);
      expect(scopeOf(tester).dataController.sessionId, chat);
      await disposeTestApp(tester, dependencies);
    });
  });

  group('overflow', () {
    testWidgets('a long title ends with an ellipsis', (tester) async {
      useWindow(tester, 1280, 800);
      final longTitle = 'Refactor the booking flow ${'and then some more ' * 10}';
      final longName = 'a-very-long-project-name-${'x' * 80}';
      await tester.runAsync(() async {
        final project = await addProject(longName);
        await addChat(project, longTitle);
      });
      await pumpSidebar(tester);

      final chat = tester.renderObject<RenderParagraph>(find.text(longTitle));
      expect(chat.didExceedMaxLines, isTrue);
      final project = tester.renderObject<RenderParagraph>(find.text(longName));
      expect(project.didExceedMaxLines, isTrue);
      expect(tester.takeException(), isNull);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a hundred chats scroll without overflow', (tester) async {
      useWindow(tester, 900, 600);
      await tester.runAsync(() async {
        final project = await addProject('avera-hotel');
        for (var i = 1; i <= 100; i++) {
          await addChat(project, 'Chat $i', minutes: 1000 - i);
        }
      });
      await pumpSidebar(tester);
      expect(find.text('Chat 100'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Chat 100'),
        200,
        scrollable: find.descendant(
          of: find.byType(WorkspaceSidebar),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Chat 100'), findsOneWidget);
      // The footer stays put.
      expect(find.text('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeTestApp(tester, dependencies);
    });
  });

  group('project menu', () {
    testWidgets('removing a project asks first and deletes its chats', (tester) async {
      useWindow(tester, 1280, 800);
      await tester.runAsync(() async {
        final avera = await addProject('avera-hotel');
        await addChat(avera, 'Booking screen');
      });
      await pumpSidebar(tester);

      await tester.tap(find.byTooltip('Project actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove…'));
      await tester.pumpAndSettle();
      expect(
        find.text('Remove avera-hotel? Its chats are deleted; files on disk stay.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('avera-hotel'), findsOneWidget);
      expect(find.text('Booking screen'), findsOneWidget);
      var counts = (await tester.runAsync(
        () async => (
          (await database.select(database.projectsTable).get()).length,
          (await database.select(database.sessionsTable).get()).length,
        ),
      ))!;
      expect(counts, (1, 1));

      await tester.tap(find.byTooltip('Project actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await settle(tester);
      await tester.pumpAndSettle();

      counts = (await tester.runAsync(
        () async => (
          (await database.select(database.projectsTable).get()).length,
          (await database.select(database.sessionsTable).get()).length,
        ),
      ))!;
      expect(counts, (0, 0));
      expect(find.text('avera-hotel'), findsNothing);
      expect(find.text('Booking screen'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a project with a working agent is kept and the user is told why', (tester) async {
      useWindow(tester, 1280, 800);
      await tester.runAsync(() async {
        final avera = await addProject('avera-hotel');
        final chat = await addChat(avera, 'Booking screen');
        (await dependencies.agentHub.session(chat)).status.value = SessionStatus.running;
      });
      await pumpSidebar(tester);

      await tester.tap(find.byTooltip('Project actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await settle(tester);
      await tester.pumpAndSettle();

      expect(find.text("Stop the agent in this project's chats first."), findsOneWidget);
      expect(find.text('avera-hotel'), findsOneWidget);
      expect(find.text('Booking screen'), findsOneWidget);
      final counts = (await tester.runAsync(
        () async => (
          (await database.select(database.projectsTable).get()).length,
          (await database.select(database.sessionsTable).get()).length,
        ),
      ))!;
      expect(counts, (1, 1));
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('removing the selected project clears the selection', (tester) async {
      useWindow(tester, 1280, 800);
      late int avera;
      await tester.runAsync(() async {
        avera = await addProject('avera-hotel');
      });
      await pumpSidebar(tester);
      scopeOf(tester).dataController.selectProject(avera);
      await tester.pump();

      await tester.tap(find.byTooltip('Project actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await settle(tester);
      await tester.pumpAndSettle();

      expect(scopeOf(tester).dataController.projectId, isNull);
      expect(scopeOf(tester).dataController.sessionId, isNull);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('Project settings opens the Skills screen', (tester) async {
      useWindow(tester, 1280, 800);
      await tester.runAsync(() => addProject('avera-hotel'));
      await pumpSidebar(tester);

      await tester.tap(find.byTooltip('Project actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project settings'));
      await tester.pumpAndSettle();
      expect(scopeOf(tester).dataController.view, WorkspaceView.skills);
      await disposeTestApp(tester, dependencies);
    });
  });

  group('top and bottom', () {
    testWidgets('the Project menu offers the folder picker and two coming soon items', (
      tester,
    ) async {
      useWindow(tester, 1280, 800);
      await pumpSidebar(tester);

      await tester.tap(find.text('Project'));
      await tester.pumpAndSettle();
      expect(find.text('Open folder…'), findsOneWidget);

      await tester.tap(find.text('New Flutter project…'));
      await tester.pumpAndSettle();
      expect(find.text('Coming in M4'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the footer opens Skills and Settings and names the default agent', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpSidebar(tester);
      expect(find.text('Claude Code'), findsOneWidget);
      expect(find.text('New chat'), findsOneWidget);
      expect(find.text('⌘N'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('⌘K'), findsOneWidget);

      await tester.tap(find.text('Skills'));
      await tester.pump();
      expect(scopeOf(tester).dataController.view, WorkspaceView.skills);
      scopeOf(tester).dataController.backToChat();
      await tester.pump();

      await tester.tap(find.text('Settings'));
      await tester.pump();
      expect(scopeOf(tester).dataController.view, WorkspaceView.settings);
      await disposeTestApp(tester, dependencies);
    });
  });

  group('new chat', () {
    Future<List<SessionRow>> sessions(WidgetTester tester) =>
        tester.runAsync(() => database.select(database.sessionsTable).get()).then((rows) => rows!);

    testWidgets("⌘N creates a chat in the selected chat's project", (tester) async {
      useWindow(tester, 1280, 800);
      late int avera;
      late int shop;
      late int chat;
      await tester.runAsync(() async {
        avera = await addProject('avera-hotel');
        shop = await addProject('shop_app');
        await addChat(avera, 'Booking screen');
        chat = await addChat(shop, 'Dark theme');
      });
      await pumpSidebar(tester);
      scopeOf(tester).dataController
        ..selectProject(avera)
        ..selectProject(shop)
        ..selectSession(chat);
      await tester.pump();

      await pressWithMeta(tester, LogicalKeyboardKey.keyN);
      await settle(tester);

      final rows = await sessions(tester);
      expect(rows.where((r) => r.projectId == shop), hasLength(2));
      expect(rows.where((r) => r.projectId == avera), hasLength(1));
      final created = rows.firstWhere((r) => r.projectId == shop && r.id != chat);
      expect(scopeOf(tester).dataController.sessionId, created.id);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('⌘N with projects but nothing selected starts a chat in the first group', (
      tester,
    ) async {
      useWindow(tester, 1280, 800);
      late int avera;
      late int shop;
      await tester.runAsync(() async {
        // The sidebar order: shop_app (the latest chat), avera-hotel (older), empty-one (no chats).
        avera = await addProject('avera-hotel');
        shop = await addProject('shop_app');
        await addProject('empty-one');
        await addChat(avera, 'Booking screen', minutes: 1);
        await addChat(shop, 'Dark theme', minutes: 9);
      });
      await pumpSidebar(tester);
      expect(scopeOf(tester).dataController.projectId, isNull);

      await pressWithMeta(tester, LogicalKeyboardKey.keyN);

      final rows = await sessions(tester);
      expect(rows.where((r) => r.projectId == shop), hasLength(2));
      expect(rows.where((r) => r.projectId == avera), hasLength(1));
      final created = rows.firstWhere((r) => r.projectId == shop && r.title != 'Dark theme');
      expect(scopeOf(tester).dataController.projectId, shop);
      expect(scopeOf(tester).dataController.sessionId, created.id);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the New chat button with nothing selected starts a chat too', (tester) async {
      useWindow(tester, 1280, 800);
      late int avera;
      await tester.runAsync(() async {
        avera = await addProject('avera-hotel');
      });
      await pumpSidebar(tester);

      await tester.tap(find.text('New chat'));
      await settle(tester);

      expect((await sessions(tester)).single.projectId, avera);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('⌘N without any project does nothing', (tester) async {
      useWindow(tester, 1280, 800);
      await pumpSidebar(tester);

      await pressWithMeta(tester, LogicalKeyboardKey.keyN);
      expect(await sessions(tester), isEmpty);
      expect(scopeOf(tester).dataController.projectId, isNull);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('⌘N on Settings starts a chat and returns to the chat screen', (tester) async {
      useWindow(tester, 1280, 800);
      late int avera;
      await tester.runAsync(() async {
        avera = await addProject('avera-hotel');
      });
      await pumpSidebar(tester);
      scopeOf(tester).dataController
        ..selectProject(avera)
        ..openView(WorkspaceView.settings);
      await tester.pump();

      await pressWithMeta(tester, LogicalKeyboardKey.keyN);

      final created = (await sessions(tester)).single;
      expect(scopeOf(tester).dataController.view, WorkspaceView.chat);
      expect(scopeOf(tester).dataController.sessionId, created.id);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the New chat button of a group creates a chat in that project', (tester) async {
      useWindow(tester, 1280, 800);
      late int avera;
      await tester.runAsync(() async {
        avera = await addProject('avera-hotel');
      });
      await pumpSidebar(tester);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('avera-hotel')));
      await tester.pump();
      await tester.tap(find.byTooltip('New chat'));
      await settle(tester);

      final rows = await sessions(tester);
      expect(rows.single.projectId, avera);
      expect(scopeOf(tester).dataController.projectId, avera);
      await disposeTestApp(tester, dependencies);
    });
  });
}
