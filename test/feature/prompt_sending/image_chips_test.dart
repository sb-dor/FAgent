import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/composer_image.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/widgets/image_chips.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/memory_agents_repository.dart';
import '../../support/test_app.dart';

/// A 1×1 PNG.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

const AgentInfo _textOnlyAgent = AgentInfo(
  id: 'custom:1',
  name: 'Text only',
  status: AgentStatus.ready,
  source: AgentSource.custom,
  acceptsImages: false,
);

void main() {
  late Directory root;
  late Dependencies dependencies;
  late int projectId;

  setUp(() {
    root = Directory.systemTemp.createTempSync('image_project');
    File(p.join(root.path, 'shot.png')).writeAsBytesSync(_png);
    addTearDown(() => root.deleteSync(recursive: true));
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Shows a new chat of [agentId] and returns the chat and its runtime state.
  Future<(ChatConfigWidgetState, LiveSession)> pumpChat(
    WidgetTester tester, {
    String agentId = 'claude',
    Future<Uint8List?> Function()? clipboard,
  }) async {
    dependencies = testDependencies(
      agentsRepository: MemoryAgentsRepository(
        agents: <AgentInfo>[memoryClaudeAgent, memoryCodexAgent, _textOnlyAgent],
      ),
    );
    addTearDown(dependencies.database.close);
    final database = dependencies.database;
    final sessionId = (await tester.runAsync(() async {
      projectId = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: root.path, name: 'p'));
      return database
          .into(database.sessionsTable)
          .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: agentId));
    }))!;
    await tester.pumpWidget(
      testApp(
        dependencies: dependencies,
        ChatConfigWidget(
          sessionId: sessionId,
          project: Project(
            id: projectId,
            path: root.path,
            name: 'p',
            isFlutter: false,
            trustedAt: DateTime(2026),
          ),
          readClipboardImage: clipboard ?? () async => null,
        ),
      ),
    );
    final live = (await tester.runAsync(() => dependencies.agentHub.session(sessionId)))!;
    await settle(tester);
    return (tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget)), live);
  }

  Future<void> dropFiles(WidgetTester tester, List<String> paths) async {
    await tester.runAsync(() async {
      tester.widget<DropTarget>(find.byType(DropTarget)).onDragDone!(
        DropDoneDetails(
          files: <DropItem>[for (final path in paths) DropItemFile(path)],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }

  Finder chips() => find.descendant(of: find.byType(ImageChips), matching: find.byType(Image));

  /// [block] is the composer's image block of [bytes]: the full image, a PNG thumbnail in the
  /// app's `_meta`.
  void expectImageBlock(Map<String, Object?> block, Uint8List bytes) {
    expect(block['type'], 'image');
    expect(block['mimeType'], 'image/png');
    expect(block['data'], base64Encode(bytes));
    expect(block['_meta'], <String, Object?>{
      'flutter_code_agent': <String, Object?>{
        'thumbnail': isA<String>(),
        'thumbnailMimeType': 'image/png',
      },
    });
  }

  Future<void> tapSend(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Send'));
    await settle(tester);
  }

  testWidgets('a dropped image shows as a chip above the text and ✕ removes it', (tester) async {
    final (chat, _) = await pumpChat(tester);

    await dropFiles(tester, <String>[p.join(root.path, 'shot.png')]);

    expect(chips(), findsOneWidget);
    expect(chat.images.value.single.name, 'shot.png');
    expect(chat.images.value.single.mimeType, 'image/png');
    expect(chat.textController.text, isEmpty);
    expect(
      tester.getBottomLeft(find.byType(ImageChips)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField)).dy),
    );

    await tester.tap(find.byTooltip('Remove the image'));
    await tester.pump();

    expect(chips(), findsNothing);
    expect(chat.images.value, isEmpty);
  });

  testWidgets('an image over 5 MB is refused with one line', (tester) async {
    final (chat, _) = await pumpChat(tester);
    final big = p.join(root.path, 'big.png');
    File(big).writeAsBytesSync(Uint8List(5 * 1024 * 1024 + 1));

    await dropFiles(tester, <String>[big]);
    await tester.pump();

    expect(chat.images.value, isEmpty);
    expect(find.text('big.png is larger than 5 MB'), findsOneWidget);
  });

  testWidgets('the 11th image is refused', (tester) async {
    final (chat, _) = await pumpChat(tester);
    final paths = <String>[for (var i = 0; i < 11; i++) p.join(root.path, 'shot$i.png')];
    for (final path in paths) {
      File(path).writeAsBytesSync(_png);
    }

    await dropFiles(tester, paths);
    await tester.pump();

    expect(chat.images.value, hasLength(10));
    expect(chat.images.value.last.name, 'shot9.png');
    expect(find.text('At most 10 images per message'), findsOneWidget);
  });

  testWidgets('an agent without images refuses them', (tester) async {
    final (chat, _) = await pumpChat(tester, agentId: 'custom:1');

    await dropFiles(tester, <String>[p.join(root.path, 'shot.png')]);
    await tester.pump();

    expect(chat.images.value, isEmpty);
    expect(find.text('This agent does not accept images'), findsOneWidget);
  });

  testWidgets('⌘V pastes an image from the clipboard', (tester) async {
    final (chat, _) = await pumpChat(tester, clipboard: () async => _png);
    await tester.tap(find.byType(TextField));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await settle(tester);

    expect(chat.images.value.single.bytes, _png);
    expect(chat.images.value.single.mimeType, 'image/png');
    expect(chips(), findsOneWidget);
  });

  testWidgets('⌘V without an image on the clipboard adds nothing', (tester) async {
    final (chat, _) = await pumpChat(tester);
    await tester.tap(find.byType(TextField));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await settle(tester);

    expect(chat.images.value, isEmpty);
  });

  testWidgets('an image that cannot be decoded is refused with one line', (tester) async {
    final (chat, _) = await pumpChat(tester);
    final broken = p.join(root.path, 'broken.png');
    File(broken).writeAsStringSync('not an image');

    await dropFiles(tester, <String>[broken]);
    await tester.pump();

    expect(chat.images.value, isEmpty);
    expect(find.text('Could not read broken.png'), findsOneWidget);
  });

  testWidgets('send puts the image blocks after the text and clears the chips', (tester) async {
    final (chat, live) = await pumpChat(tester);
    await dropFiles(tester, <String>[p.join(root.path, 'shot.png')]);
    chat.textController.text = 'what is wrong here?';

    await tester.runAsync(chat.send);
    await settle(tester);

    final sent = live.lastPrompt!;
    expect(sent, hasLength(2));
    expect(sent.first, <String, Object?>{'type': 'text', 'text': 'what is wrong here?'});
    expectImageBlock(sent.last, _png);
    expect(chat.images.value, isEmpty);
    expect(chips(), findsNothing);
    // Lets the hub's start attempt end.
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets('a queued message keeps its images and ✎ puts them back', (tester) async {
    final (chat, live) = await pumpChat(tester);
    live.status.value = SessionStatus.running;
    await settle(tester);
    await dropFiles(tester, <String>[p.join(root.path, 'shot.png')]);
    chat.textController.text = 'then this';

    await tester.runAsync(chat.queue);
    await settle(tester);

    final queued = chat.queueController.state.items.single;
    // Kept once, as the image: its block is built when the message goes.
    expect(queued.resources, isEmpty);
    expect(queued.images.single.bytes, _png);
    expectImageBlock(queued.blocks.last, _png);
    expect(queued.attachmentCount, 1);
    expect(chat.images.value, isEmpty);
    expect(chat.textController.text, isEmpty);

    chat.editQueued(0);
    await tester.pump();

    expect(chat.textController.text, 'then this');
    expect(chat.images.value.single.bytes, _png);
    expect(chat.queueController.state.items, isEmpty);
    expect(chips(), findsOneWidget);
  });

  testWidgets('images alone can be sent; the prompt has no text block', (tester) async {
    final (chat, live) = await pumpChat(tester);
    await dropFiles(tester, <String>[p.join(root.path, 'shot.png')]);
    expect(chat.textController.text, isEmpty);

    await tapSend(tester);

    final sent = live.lastPrompt!;
    expectImageBlock(sent.single, _png);
    expect(chat.images.value, isEmpty);
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets('✎ that would pass 10 images keeps 10 and says so', (tester) async {
    final (chat, live) = await pumpChat(tester);
    live.status.value = SessionStatus.running;
    await settle(tester);
    final paths = <String>[for (var i = 0; i < 6; i++) p.join(root.path, 'shot$i.png')];
    for (final path in paths) {
      File(path).writeAsBytesSync(_png);
    }
    await dropFiles(tester, paths);
    chat.textController.text = 'first';
    await tester.runAsync(chat.queue);
    await settle(tester);
    await dropFiles(tester, paths);
    expect(chat.images.value, hasLength(6));

    chat.editQueued(0);
    await tester.pump();

    expect(chat.images.value, hasLength(10));
    expect(find.text('At most 10 images per message'), findsOneWidget);
  });

  testWidgets('a composer image keeps a PNG thumbnail of at most 256 px', (tester) async {
    late ComposerImage image;
    late ui.Image thumbnail;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
          .drawRect(const Rect.fromLTWH(0, 0, 1000, 500), Paint()..color = const Color(0xFF336699));
      final picture = await recorder.endRecording().toImage(1000, 500);
      final bytes = (await picture.toByteData(format: ui.ImageByteFormat.png))!;
      image = await ComposerImage.of(
        name: 'wide.png',
        mimeType: 'image/png',
        bytes: bytes.buffer.asUint8List(),
      );
      final codec = await ui.instantiateImageCodec(image.thumbnail);
      thumbnail = (await codec.getNextFrame()).image;
    });

    expect((thumbnail.width, thumbnail.height), (256, 128));
    expect(image.thumbnail.length, lessThan(image.bytes.length));
    final block = image.toBlock();
    expect((block['_meta']! as Map<String, Object?>)['flutter_code_agent'], <String, Object?>{
      'thumbnail': base64Encode(image.thumbnail),
      'thumbnailMimeType': 'image/png',
    });
  });
}
