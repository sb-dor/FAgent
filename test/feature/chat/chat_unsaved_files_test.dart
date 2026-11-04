import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_code_files_repository.dart';
import '../../support/test_app.dart';

void main() {
  const root = '/tmp/unsaved_app';
  late MemoryCodeFilesRepository files;
  late Dependencies dependencies;
  late int projectId;

  setUp(() {
    files = MemoryCodeFilesRepository(files: <String, String>{'$root/lib/main.dart': 'a\n'});
    dependencies = testDependencies(codeFilesRepository: files);
    addTearDown(dependencies.database.close);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Shows a new chat of the project with one unsaved file and returns its runtime state.
  Future<(LiveSession, CodeDocument)> show(WidgetTester tester) async {
    final database = dependencies.database;
    final sessionId = (await tester.runAsync(() async {
      projectId = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: root, name: 'app'));
      return database
          .into(database.sessionsTable)
          .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: 'claude'));
    }))!;
    final document = (await tester.runAsync(
      () => dependencies.codeViews
          .workspaceFor(projectId: projectId, root: root)
          .tabs
          .open('$root/lib/main.dart'),
    ))!;
    document.editing.replaceSelection('x');
    await tester.pumpWidget(
      testApp(
        dependencies: dependencies,
        ChatConfigWidget(
          key: ValueKey<int>(sessionId),
          sessionId: sessionId,
          project: Project(
            id: projectId,
            path: root,
            name: 'app',
            isFlutter: false,
            trustedAt: DateTime(2026),
          ),
        ),
      ),
    );
    final live = (await tester.runAsync(() => dependencies.agentHub.session(sessionId)))!;
    await settle(tester);
    return (live, document);
  }

  ChatConfigWidgetState chat(WidgetTester tester) =>
      tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  const bar = '1 unsaved file — the agent sees the version on disk';

  testWidgets('sending with unsaved files shows the bar and keeps the text', (tester) async {
    await show(tester);
    await type(tester, 'fix it');

    await tester.runAsync(chat(tester).send);
    await settle(tester);

    expect(find.text(bar), findsOneWidget);
    expect(chat(tester).textController.text, 'fix it');
  });

  testWidgets('Save all saves and sends', (tester) async {
    final (_, document) = await show(tester);
    await type(tester, 'fix it');
    await tester.runAsync(chat(tester).send);
    await settle(tester);

    await tester.tap(find.text('Save all'));
    await settle(tester);
    await settle(tester);

    expect(document.dirty, isFalse);
    expect(files.files['$root/lib/main.dart'], 'xa\n');
    expect(find.text(bar), findsNothing);
    expect(chat(tester).textController.text, isEmpty);
  });

  testWidgets('Send anyway sends without saving', (tester) async {
    final (_, document) = await show(tester);
    await type(tester, 'fix it');
    await tester.runAsync(chat(tester).send);
    await settle(tester);

    await tester.tap(find.text('Send anyway'));
    await settle(tester);
    await settle(tester);

    expect(document.dirty, isTrue);
    expect(find.text(bar), findsNothing);
    expect(chat(tester).textController.text, isEmpty);
  });

  testWidgets('⌘↵ queue shows the same bar, Send anyway queues', (tester) async {
    final (live, _) = await show(tester);
    live.status.value = SessionStatus.running;
    await settle(tester);
    await type(tester, 'then add tests');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await settle(tester);
    expect(find.text(bar), findsOneWidget);
    expect(chat(tester).textController.text, 'then add tests');

    await tester.tap(find.text('Send anyway'));
    await settle(tester);
    await settle(tester);

    expect(chat(tester).textController.text, isEmpty);
    expect(find.text('then add tests'), findsOneWidget);
  });

  testWidgets('the bar goes away once the files are saved elsewhere', (tester) async {
    final (_, document) = await show(tester);
    await type(tester, 'fix it');
    await tester.runAsync(chat(tester).send);
    await settle(tester);

    await tester.runAsync(document.save);
    await settle(tester);

    expect(find.text(bar), findsNothing);
    expect(chat(tester).textController.text, 'fix it');
  });

  testWidgets('without unsaved files sending shows no bar', (tester) async {
    final (_, document) = await show(tester);
    await tester.runAsync(document.save);
    await type(tester, 'fix it');

    await tester.runAsync(chat(tester).send);
    await settle(tester);

    expect(find.text(bar), findsNothing);
    expect(chat(tester).textController.text, isEmpty);
  });
}
