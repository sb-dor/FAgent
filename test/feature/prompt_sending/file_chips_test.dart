import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/drop_zone/drop_zone.dart';
import 'package:flutter_code_agent/src/common/drop_zone/drop_zone_event.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_drop_target.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/composer_file.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/widgets/file_chips.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/test_app.dart';

void main() {
  late Directory root;
  late Directory outside;
  late Dependencies dependencies;
  late StreamController<DropZoneEvent> dropEvents;

  setUp(() {
    dropEvents = StreamController<DropZoneEvent>.broadcast();
    addTearDown(dropEvents.close);
    root = Directory.systemTemp.createTempSync('file_cards_project');
    outside = Directory.systemTemp.createTempSync('file_cards_outside');
    File(p.join(root.path, 'notes.md')).writeAsStringSync('notes');
    File(p.join(outside.path, 'shot.heic')).writeAsBytesSync(<int>[1, 2, 3]);
    Directory(p.join(outside.path, 'Downloads')).createSync();
    addTearDown(() {
      root.deleteSync(recursive: true);
      outside.deleteSync(recursive: true);
    });
  });

  String heic() => p.join(outside.path, 'shot.heic');
  String folder() => p.join(outside.path, 'Downloads');

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<(ChatConfigWidgetState, LiveSession)> pumpChat(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    Locale locale = const Locale('en'),
    bool dark = false,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    dependencies = testDependencies(dropZone: DropZone.fromStream(dropEvents.stream));
    addTearDown(dependencies.database.close);
    final database = dependencies.database;
    late int projectId;
    final sessionId = (await tester.runAsync(() async {
      projectId = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: root.path, name: 'p'));
      return database
          .into(database.sessionsTable)
          .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: 'claude'));
    }))!;
    await tester.pumpWidget(
      testApp(
        dependencies: dependencies,
        locale: locale,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        ChatConfigWidget(
          sessionId: sessionId,
          project: Project(
            id: projectId,
            path: root.path,
            name: 'p',
            isFlutter: false,
            trustedAt: DateTime(2026),
          ),
        ),
      ),
    );
    final live = (await tester.runAsync(() => dependencies.agentHub.session(sessionId)))!;
    await settle(tester);
    return (tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget)), live);
  }

  Future<void> dropFiles(WidgetTester tester, List<String> paths) async {
    final at = tester.getCenter(find.byType(ChatDropTarget));
    dropEvents.add(DropZoneEvent$Drop(dx: at.dx, dy: at.dy, paths: paths));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    await tester.pump();
  }

  Finder cards() => find.byType(FileCard);

  testWidgets('an outside file and folder become cards, the text stays as typed', (tester) async {
    final (chat, _) = await pumpChat(tester);
    chat.textController.text = 'compare';

    await dropFiles(tester, <String>[heic(), folder(), p.join(root.path, 'notes.md')]);

    expect(chat.files.value, <ComposerFile>[
      ComposerFile(path: heic()),
      ComposerFile(path: folder(), folder: true),
    ]);
    expect(chat.textController.text, 'compare @notes.md ');
    expect(cards(), findsNWidgets(2));
    expect(find.text('HEIC'), findsOneWidget);
    expect(find.text('Folder'), findsOneWidget);
    expect(find.byTooltip(heic()), findsOneWidget);
  });

  testWidgets('✕ removes a card and a second drop of the same path is ignored', (tester) async {
    final (chat, _) = await pumpChat(tester);
    await dropFiles(tester, <String>[heic()]);
    await dropFiles(tester, <String>[heic()]);
    expect(chat.files.value, hasLength(1));

    await tester.tap(find.byTooltip('Remove the file'));
    await tester.pump();

    expect(chat.files.value, isEmpty);
    expect(cards(), findsNothing);
  });

  testWidgets('send puts the links after the text and clears the cards', (tester) async {
    final (chat, live) = await pumpChat(tester);
    await dropFiles(tester, <String>[heic()]);
    chat.textController.text = 'what is in it?';

    await tester.runAsync(chat.send);
    await settle(tester);

    final sent = live.lastPrompt!;
    expect(sent.first, <String, Object?>{'type': 'text', 'text': 'what is in it?'});
    expect(sent.last, ComposerFile(path: heic()).toBlock());
    expect(chat.files.value, isEmpty);
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets('cards alone can be sent', (tester) async {
    final (chat, live) = await pumpChat(tester);
    await dropFiles(tester, <String>[heic()]);

    await tester.tap(find.byTooltip('Send'));
    await settle(tester);

    expect(live.lastPrompt, <Map<String, Object?>>[ComposerFile(path: heic()).toBlock()]);
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets('a queued message keeps its cards and ✎ puts them back', (tester) async {
    final (chat, live) = await pumpChat(tester);
    live.status.value = SessionStatus.running;
    await settle(tester);
    await dropFiles(tester, <String>[heic()]);
    chat.textController.text = 'then this';

    await tester.runAsync(chat.queue);
    await settle(tester);

    final queued = chat.queueController.state.items.single;
    expect(queued.files, <ComposerFile>[ComposerFile(path: heic())]);
    expect(queued.blocks.last, ComposerFile(path: heic()).toBlock());
    expect(queued.attachmentCount, 1);
    expect(chat.files.value, isEmpty);

    chat.editQueued(0);
    await tester.pump();

    expect(chat.files.value, <ComposerFile>[ComposerFile(path: heic())]);
    expect(cards(), findsOneWidget);
  });

  for (final locale in const <Locale>[Locale('en'), Locale('ru')]) {
    for (final dark in const <bool>[false, true]) {
      testWidgets('cards fit at 900×600 in ${locale.languageCode}, ${dark ? 'dark' : 'light'}', (
        tester,
      ) async {
        final (chat, _) = await pumpChat(
          tester,
          size: const Size(900, 600),
          locale: locale,
          dark: dark,
        );
        final long = p.join(outside.path, '${'Снимок экрана — 2026-11-04 в 15.53.33' * 2}.heic');
        File(long).writeAsBytesSync(<int>[1]);

        await dropFiles(tester, <String>[long, heic(), folder()]);

        expect(chat.files.value, hasLength(3));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
