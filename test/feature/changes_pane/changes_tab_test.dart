import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/widget/diff_view.dart';
import 'package:flutter_code_agent/src/feature/changes_pane/models/changed_file.dart';
import 'package:flutter_code_agent/src/feature/changes_pane/widgets/changes_view.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_handle.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  ToolDiffContent diff(String path, String before, String after) =>
      ToolDiffContent(path: path, oldText: before, newText: after);

  final files = <ChangedFile>[
    ChangedFile(
      path: '/p/lib/booking_screen.dart',
      status: 'modified',
      diffs: <ToolDiffContent>[diff('/p/lib/booking_screen.dart', 'a\n', 'a\nb\nc\n')],
    ),
    const ChangedFile(path: '/p/pubspec.lock', status: 'modified', diffs: <ToolDiffContent>[]),
    ChangedFile(
      path: '/p/intl_ru.arb',
      status: 'edited',
      diffs: <ToolDiffContent>[diff('/p/intl_ru.arb', 'x\ny\n', 'x\nz\n')],
    ),
  ];

  Widget view({
    List<ChangedFile>? changes,
    String? selected,
    ValueChanged<String?>? onSelect,
    ValueChanged<String>? onOpenFile,
  }) => testApp(
    ChangesView(
      files: changes ?? files,
      projectRoot: '/p',
      selectedPath: selected,
      onSelect: onSelect ?? (_) {},
      onOpenFile: onOpenFile ?? (_) {},
    ),
  );

  testWidgets('the first file is shown when none is chosen', (tester) async {
    useDesktopView(tester);
    await tester.pumpWidget(view());

    expect(find.textContaining('booking_screen.dart'), findsWidgets);
    expect(find.text('+2'), findsWidgets);
    expect(find.byType(DiffView), findsOneWidget);
  });

  testWidgets('a path that is not listed falls back to the first file', (tester) async {
    useDesktopView(tester);
    await tester.pumpWidget(view(selected: '/p/gone.dart'));

    expect(find.byType(DiffView), findsOneWidget);
    expect(find.textContaining('booking_screen.dart'), findsWidgets);
  });

  testWidgets('picking a file shows its diff', (tester) async {
    useDesktopView(tester);
    String? picked;
    await tester.pumpWidget(view(selected: '/p/intl_ru.arb', onSelect: (path) => picked = path));

    final diffView = tester.widget<DiffView>(find.byType(DiffView));
    expect(diffView.path, '/p/intl_ru.arb');

    await tester.tap(find.textContaining('booking_screen.dart'));
    expect(picked, '/p/lib/booking_screen.dart');
  });

  testWidgets('a file changed by a command offers to open it', (tester) async {
    useDesktopView(tester);
    String? opened;
    await tester.pumpWidget(view(selected: '/p/pubspec.lock', onOpenFile: (path) => opened = path));

    expect(find.byType(DiffView), findsNothing);
    expect(find.text('Changed by a command, there is no diff to show.'), findsOneWidget);
    await tester.tap(find.text('Open file'));
    expect(opened, '/p/pubspec.lock');
  });

  testWidgets('no changes shows the empty state', (tester) async {
    useDesktopView(tester);
    await tester.pumpWidget(view(changes: const <ChangedFile>[]));

    expect(find.text('No changes yet'), findsOneWidget);
  });

  testWidgets('a narrow pane in a small window does not overflow', (tester) async {
    tester.view
      ..physicalSize = const Size(340, 400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(view(selected: '/p/lib/booking_screen.dart'));

    expect(tester.takeException(), isNull);
  });

  group('in the right pane', () {
    late Dependencies dependencies;
    late int sessionId;

    setUp(() => dependencies = testDependencies());

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<WorkspaceConfigWidgetState> pump(WidgetTester tester, {Size? size}) async {
      tester.view
        ..physicalSize = size ?? const Size(1280, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      sessionId = (await tester.runAsync(() async {
        final database = dependencies.database;
        final project = await database
            .into(database.projectsTable)
            .insert(ProjectsTableCompanion.insert(path: '/p', name: 'p'));
        return database
            .into(database.sessionsTable)
            .insert(
              SessionsTableCompanion.insert(
                projectId: project,
                agentId: 'claude',
                title: const Value<String>('Chat'),
              ),
            );
      }))!;
      await tester.pumpWidget(
        testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
      );
      await settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat'));
      for (var i = 0; i < 5; i++) {
        await settle(tester);
      }
      return WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));
    }

    void publish(WorkspaceConfigWidgetState state, List<ChatItem> items) =>
        state.dataController.publishChatHandle(
          ChatHandle(
            sessionId: sessionId,
            view: ChatView(
              sessionId: sessionId,
              agentId: 'claude',
              items: items,
              status: SessionStatus.idle,
            ),
            insertDraft: (_) {},
          ),
        );

    ToolCallItem edit(int seq, String path) => ToolCallItem(
      seq,
      toolCallId: 'c$seq',
      title: 'Edit',
      kind: 'edit',
      content: <ToolContent>[ToolDiffContent(path: path, oldText: 'a\n', newText: 'a\nb\n')],
    );

    testWidgets('the tab badge counts files', (tester) async {
      final state = await pump(tester);
      expect(find.text('No changes yet'), findsOneWidget);

      publish(state, <ChatItem>[
        edit(1, '/p/lib/a.dart'),
        edit(2, '/p/lib/b.dart'),
        const TurnFilesItem(
          3,
          root: '/p',
          files: <TurnFile>[TurnFile(path: 'lib/a.dart', status: ' M')],
        ),
      ]);
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
      expect(find.textContaining('a.dart'), findsWidgets);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('selecting a change from the feed shows that file', (tester) async {
      final state = await pump(tester);
      publish(state, <ChatItem>[edit(1, '/p/lib/a.dart'), edit(2, '/p/lib/b.dart')]);
      await tester.pump();
      state.dataController.selectChange('/p/lib/a.dart');
      await tester.pump();

      expect(tester.widget<DiffView>(find.byType(DiffView)).path, '/p/lib/a.dart');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('900×600 with files does not overflow', (tester) async {
      final state = await pump(tester, size: const Size(900, 600));
      publish(state, <ChatItem>[
        for (var i = 0; i < 12; i++) edit(i, '/p/lib/some/deep/folder/file_$i.dart'),
      ]);
      state.openChange('/p/lib/some/deep/folder/file_3.dart');
      await settle(tester);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(tester.widget<DiffView>(find.byType(DiffView)).path, endsWith('file_3.dart'));
      await disposeTestApp(tester, dependencies);
    });
  });
}
