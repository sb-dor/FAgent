import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/chat_search/controller/chat_search_controller.dart';
import 'package:flutter_code_agent/src/feature/chat_search/data/chat_search_repository.dart';
import 'package:flutter_code_agent/src/feature/chat_search/models/chat_search_result.dart';
import 'package:flutter_code_agent/src/feature/chat_search/widgets/chat_search_dialog.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

/// Lets drift's real-async work finish, then rebuilds.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 100));
}

final searchField = find.descendant(
  of: find.byType(ChatSearchDialog),
  matching: find.byType(TextField),
);

/// Answers each query when the test completes it.
class _ManualRepository implements IChatSearchRepository {
  final Map<String, Completer<List<ChatSearchResult>>> answers =
      <String, Completer<List<ChatSearchResult>>>{};

  @override
  Future<List<ChatSearchResult>> search(String query, {int limit = 20}) =>
      (answers[query] ??= Completer<List<ChatSearchResult>>()).future;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late AppDatabase database;

  setUp(() {
    dependencies = testDependencies();
    database = dependencies.database;
  });

  Future<int> addProject(String name) => database
      .into(database.projectsTable)
      .insert(ProjectsTableCompanion.insert(path: '/work/$name', name: name));

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

  group('ChatSearchRepositoryImpl', () {
    late ChatSearchRepositoryImpl repository;

    setUp(() => repository = ChatSearchRepositoryImpl(database: database));

    test('search matches titles regardless of case', () async {
      final project = await addProject('shop');
      final chat = await addChat(project, 'Экран бронирования');
      await addChat(project, 'Другое');

      for (final query in <String>['бронир', 'БРОНИР', 'Экран']) {
        final results = await repository.search(query);
        expect(results.map((r) => r.sessionId), <int>[chat], reason: query);
      }
      final result = (await repository.search('бронир')).single;
      expect(result.projectId, project);
      expect(result.projectName, 'shop');
      expect(result.title, 'Экран бронирования');
    });

    test('wildcards are searched literally', () async {
      final project = await addProject('shop');
      final percent = await addChat(project, '100% done');
      await addChat(project, '100 done');
      final underscore = await addChat(project, 'a_b');
      await addChat(project, 'ab');
      await addChat(project, r'back\slash');

      expect((await repository.search('%')).map((r) => r.sessionId), <int>[percent]);
      expect((await repository.search('_')).map((r) => r.sessionId), <int>[underscore]);
      expect(await repository.search(r'\'), hasLength(1));
      expect(await repository.search("'"), isEmpty);
    });

    test('an empty query lists recent chats, newest first, up to the limit', () async {
      final project = await addProject('shop');
      final old = await addChat(project, 'old');
      final fresh = await addChat(project, 'fresh', minutes: 10);
      final middle = await addChat(project, 'middle', minutes: 5);

      expect((await repository.search('')).map((r) => r.sessionId), <int>[fresh, middle, old]);
      expect((await repository.search('  ')).map((r) => r.sessionId), <int>[fresh, middle, old]);
      expect((await repository.search('', limit: 2)).map((r) => r.sessionId), <int>[fresh, middle]);
    });
  });

  test('the controller drops the answer to a query that is no longer the latest', () async {
    final repository = _ManualRepository();
    final controller = ChatSearchController(repository: repository);
    addTearDown(controller.dispose);
    final stale = ChatSearchResult(
      sessionId: 1,
      projectId: 1,
      title: 'old',
      projectName: 'p',
      updatedAt: DateTime(2026),
    );

    controller.search('a');
    await Future<void>.delayed(Duration.zero);
    controller.search('ab');
    // The answer to 'a' comes after 'ab' was asked, so it is thrown away.
    repository.answers['a']!.complete(<ChatSearchResult>[stale]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, isNot(isA<ChatSearch$CompletedState>()));
    repository.answers['ab']!.complete(const <ChatSearchResult>[]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      controller.state,
      isA<ChatSearch$CompletedState>()
          .having((s) => s.query, 'query', 'ab')
          .having((s) => s.results, 'results', isEmpty),
    );
  });

  group('⌘K', () {
    testWidgets('⌘K opens search and Enter opens the chat', (tester) async {
      useDesktopView(tester);
      final shop = await tester.runAsync(() => addProject('shop')) ?? 0;
      final avera = await tester.runAsync(() => addProject('avera')) ?? 0;
      final first = await tester.runAsync(() => addChat(shop, 'Booking screen', minutes: 2)) ?? 0;
      final second = await tester.runAsync(() => addChat(avera, 'Booking api', minutes: 1)) ?? 0;
      await tester.runAsync(() => addChat(shop, 'Unrelated', minutes: 3));
      await tester.pumpWidget(
        testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
      );
      await settle(tester);
      await tester.pumpAndSettle();
      final scope = tester.state<WorkspaceConfigWidgetState>(find.byType(WorkspaceConfigWidget));
      scope.dataController.openView(WorkspaceView.settings);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();
      expect(find.text('Search chats…'), findsOneWidget);

      await tester.enterText(searchField, 'booking');
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('Booking screen'), findsWidgets);
      expect(find.text('Unrelated'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      await tester.pumpAndSettle();

      expect(find.text('Search chats…'), findsNothing);
      expect(scope.dataController.projectId, avera);
      expect(scope.dataController.sessionId, second);
      expect(scope.dataController.view, WorkspaceView.chat);
      expect(first, isNot(second));
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('Esc closes search without choosing', (tester) async {
      useDesktopView(tester);
      final shop = await tester.runAsync(() => addProject('shop')) ?? 0;
      await tester.runAsync(() => addChat(shop, 'Booking screen'));
      await tester.pumpWidget(
        testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
      );
      await settle(tester);
      await tester.pumpAndSettle();
      final scope = tester.state<WorkspaceConfigWidgetState>(find.byType(WorkspaceConfigWidget));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();
      expect(find.text('Search chats…'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Search chats…'), findsNothing);
      expect(scope.dataController.sessionId, isNull);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a query without matches says so', (tester) async {
      useDesktopView(tester);
      final shop = await tester.runAsync(() => addProject('shop')) ?? 0;
      await tester.runAsync(() => addChat(shop, 'Booking screen'));
      await tester.pumpWidget(
        testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
      );
      await settle(tester);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();
      await tester.enterText(searchField, 'zzz');
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('No chats found'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await disposeTestApp(tester, dependencies);
    });
  });
}
