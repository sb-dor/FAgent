import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/drop_zone/drop_zone.dart';
import 'package:flutter_code_agent/src/common/drop_zone/drop_zone_event.dart';
import 'package:flutter_code_agent/src/common/widget/drop_zone_overlay.dart';
import 'package:flutter_code_agent/src/feature/chat/models/drop_classification.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_drop_target.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/test_app.dart';

void main() {
  late Directory root;
  late Directory outside;

  setUp(() {
    root = Directory.systemTemp.createTempSync('drop_project');
    outside = Directory.systemTemp.createTempSync('drop_outside');
    File(p.join(root.path, 'notes.md')).writeAsStringSync('notes');
    Directory(p.join(root.path, 'lib', 'src')).createSync(recursive: true);
    File(p.join(root.path, 'lib', 'main.dart')).writeAsStringSync('void main() {}');
    File(p.join(outside.path, 'secret.txt')).writeAsStringSync('secret');
    addTearDown(() {
      root.deleteSync(recursive: true);
      outside.deleteSync(recursive: true);
    });
  });

  group('classifyDrop', () {
    test('a project file is an @relative mention', () {
      final dropped = classifyDrop(<String>[
        p.join(root.path, 'lib', 'main.dart'),
      ], projectRoot: root.path);

      expect(dropped, <DroppedPath>[const DropMention('lib/main.dart')]);
      expect(dropped.single.text, '@lib/main.dart');
    });

    test('a project folder is an @relative/ mention', () {
      final dropped = classifyDrop(<String>[
        p.join(root.path, 'lib', 'src'),
      ], projectRoot: root.path);

      expect(dropped, <DroppedPath>[const DropMention('lib/src', folder: true)]);
      expect(dropped.single.text, '@lib/src/');
    });

    test('a file outside the project is its absolute path', () {
      final path = p.join(outside.path, 'secret.txt');

      final dropped = classifyDrop(<String>[path], projectRoot: root.path);

      expect(dropped, <DroppedPath>[DropAbsolute(path)]);
      expect(dropped.single.text, path);
    });

    test('a folder outside the project is its absolute path', () {
      final dropped = classifyDrop(<String>[outside.path], projectRoot: root.path);

      expect(dropped, <DroppedPath>[DropAbsolute(outside.path)]);
    });

    test('an outside path with spaces is wrapped in backticks', () {
      final path = p.join(outside.path, 'My Notes', 'plan.txt');
      File(path).createSync(recursive: true);

      final dropped = classifyDrop(<String>[path], projectRoot: root.path);

      expect(dropped.single.text, '`$path`');
    });

    test('an image extension is an image, inside the project or not', () {
      final inside = p.join(root.path, 'shot.PNG');
      final elsewhere = p.join(outside.path, 'photo.jpeg');
      File(inside).writeAsBytesSync(<int>[1]);
      File(elsewhere).writeAsBytesSync(<int>[1]);

      final dropped = classifyDrop(<String>[inside, elsewhere], projectRoot: root.path);

      expect(dropped, <DroppedPath>[DropImage(inside), DropImage(elsewhere)]);
    });

    test('several paths keep the drop order', () {
      final secret = p.join(outside.path, 'secret.txt');
      final image = p.join(outside.path, 'a.webp');
      File(image).writeAsBytesSync(<int>[1]);

      final dropped = classifyDrop(<String>[
        secret,
        p.join(root.path, 'notes.md'),
        image,
        p.join(root.path, 'lib'),
      ], projectRoot: root.path);

      expect(dropped, <DroppedPath>[
        DropAbsolute(secret),
        const DropMention('notes.md'),
        DropImage(image),
        const DropMention('lib', folder: true),
      ]);
    });
  });

  group('ChatDropTarget', () {
    late StreamController<DropZoneEvent> events;
    late List<List<String>> dropped;

    setUp(() {
      events = StreamController<DropZoneEvent>.broadcast();
      dropped = <List<String>>[];
      addTearDown(events.close);
    });

    /// A 300 px sidebar and the drop target filling the rest of a 1280×800 window.
    Widget layout({bool hidden = false, Stream<DropZoneEvent>? stream}) => Row(
      children: <Widget>[
        const SizedBox(width: 300, child: Text('sidebar')),
        Expanded(
          child: TickerMode(
            enabled: !hidden,
            child: Offstage(
              offstage: hidden,
              child: ChatDropTarget(
                events: stream ?? events.stream,
                onDropped: dropped.add,
                child: const SizedBox.expand(child: Text('chat')),
              ),
            ),
          ),
        ),
      ],
    );

    Future<void> pumpTarget(WidgetTester tester, {bool hidden = false}) async {
      useDesktopView(tester);
      await tester.pumpWidget(testApp(layout(hidden: hidden)));
    }

    Future<void> send(WidgetTester tester, DropZoneEvent event) async {
      events.add(event);
      await tester.pump();
      await tester.pump();
    }

    const inside = (dx: 800.0, dy: 400.0);
    const outside = (dx: 100.0, dy: 400.0);

    testWidgets('enter inside shows the overlay', (tester) async {
      await pumpTarget(tester);
      expect(find.byType(DropZoneOverlay), findsNothing);

      await send(tester, DropZoneEvent$Enter(dx: inside.dx, dy: inside.dy));

      expect(find.byType(DropZoneOverlay), findsOneWidget);
      expect(find.text('Drop files here'), findsOneWidget);
      expect(find.text('to attach them to your message'), findsOneWidget);
    });

    testWidgets('enter outside does not show the overlay', (tester) async {
      await pumpTarget(tester);

      await send(tester, DropZoneEvent$Enter(dx: outside.dx, dy: outside.dy));

      expect(find.byType(DropZoneOverlay), findsNothing);
    });

    testWidgets('over outside hides it, over inside shows it again', (tester) async {
      await pumpTarget(tester);
      await send(tester, DropZoneEvent$Enter(dx: inside.dx, dy: inside.dy));

      await send(tester, DropZoneEvent$Over(dx: outside.dx, dy: outside.dy));
      expect(find.byType(DropZoneOverlay), findsNothing);

      await send(tester, DropZoneEvent$Over(dx: inside.dx, dy: inside.dy));
      expect(find.byType(DropZoneOverlay), findsOneWidget);
    });

    testWidgets('leave hides it', (tester) async {
      await pumpTarget(tester);
      await send(tester, DropZoneEvent$Enter(dx: inside.dx, dy: inside.dy));

      await send(tester, DropZoneEvent$Leave(dx: inside.dx, dy: inside.dy));

      expect(find.byType(DropZoneOverlay), findsNothing);
    });

    testWidgets('drop inside passes the paths in order and hides the overlay', (tester) async {
      await pumpTarget(tester);
      await send(tester, DropZoneEvent$Enter(dx: inside.dx, dy: inside.dy));

      await send(
        tester,
        DropZoneEvent$Drop(dx: inside.dx, dy: inside.dy, paths: const <String>['/b', '/a', '/c']),
      );

      expect(dropped, <List<String>>[
        <String>['/b', '/a', '/c'],
      ]);
      expect(find.byType(DropZoneOverlay), findsNothing);
    });

    testWidgets('drop outside is ignored', (tester) async {
      await pumpTarget(tester);
      await send(tester, DropZoneEvent$Enter(dx: inside.dx, dy: inside.dy));

      await send(
        tester,
        DropZoneEvent$Drop(dx: outside.dx, dy: outside.dy, paths: const <String>['/a']),
      );

      expect(dropped, isEmpty);
      expect(find.byType(DropZoneOverlay), findsNothing);
    });

    testWidgets('a hidden (Offstage/TickerMode off) chat ignores events', (tester) async {
      await pumpTarget(tester, hidden: true);

      await send(tester, DropZoneEvent$Enter(dx: inside.dx, dy: inside.dy));
      expect(find.byType(DropZoneOverlay, skipOffstage: false), findsNothing);
      await send(
        tester,
        DropZoneEvent$Drop(
          dx: inside.dx,
          dy: inside.dy,
          paths: const <String>['/a'],
          failed: 1,
        ),
      );

      expect(dropped, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a chat under a dialog ignores events', (tester) async {
      await pumpTarget(tester);
      showDialog<void>(
        context: tester.element(find.text('chat')),
        builder: (context) => const AlertDialog(content: Text('dialog')),
      );
      await tester.pumpAndSettle();

      await send(tester, DropZoneEvent$Enter(dx: inside.dx, dy: inside.dy));
      expect(find.byType(DropZoneOverlay), findsNothing);
      await send(
        tester,
        DropZoneEvent$Drop(dx: inside.dx, dy: inside.dy, paths: const <String>['/a']),
      );

      expect(dropped, isEmpty);
    });

    testWidgets('a drop with no paths and failed > 0 shows the line', (tester) async {
      await pumpTarget(tester);

      await send(tester, DropZoneEvent$Drop(dx: inside.dx, dy: inside.dy, failed: 2));

      expect(dropped, isEmpty);
      expect(find.text("Couldn't get the dropped files"), findsOneWidget);
    });

    testWidgets('a drop with paths and failed > 0 passes the paths and shows the line', (
      tester,
    ) async {
      await pumpTarget(tester);

      await send(
        tester,
        DropZoneEvent$Drop(dx: inside.dx, dy: inside.dy, paths: const <String>['/a'], failed: 1),
      );

      expect(dropped, <List<String>>[
        <String>['/a'],
      ]);
      expect(find.text("Couldn't get the dropped files"), findsOneWidget);
    });

    testWidgets('a new events stream is followed instead of the old one', (tester) async {
      await pumpTarget(tester);
      final other = StreamController<DropZoneEvent>.broadcast();
      addTearDown(other.close);
      await tester.pumpWidget(testApp(layout(stream: other.stream)));

      await send(
        tester,
        DropZoneEvent$Drop(dx: inside.dx, dy: inside.dy, paths: const <String>['/old']),
      );
      other.add(DropZoneEvent$Drop(dx: inside.dx, dy: inside.dy, paths: const <String>['/new']));
      await tester.pump();

      expect(dropped, <List<String>>[
        <String>['/new'],
      ]);
    });
  });

  group('the chat', () {
    late Dependencies dependencies;
    late StreamController<DropZoneEvent> events;

    setUp(() {
      events = StreamController<DropZoneEvent>.broadcast();
      addTearDown(events.close);
      dependencies = testDependencies(dropZone: DropZone.fromStream(events.stream));
      addTearDown(dependencies.database.close);
    });

    Future<ChatConfigWidgetState> pumpChat(WidgetTester tester) async {
      await tester.pumpWidget(
        testApp(
          dependencies: dependencies,
          ChatConfigWidget(
            sessionId: 404,
            project: Project(id: 1, path: root.path, name: 'p', isFlutter: false),
          ),
        ),
      );
      await tester.pump();
      return tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));
    }

    Offset chatCenter(WidgetTester tester) => tester.getCenter(find.byType(ChatDropTarget));

    /// The chat listens in the test's fake-async zone, so the drop's file-system work is let run
    /// in real time between pumps.
    Future<void> dropFiles(WidgetTester tester, List<String> paths) async {
      final at = chatCenter(tester);
      events.add(DropZoneEvent$Drop(dx: at.dx, dy: at.dy, paths: paths));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      }
      await tester.pump();
    }

    Future<void> send(WidgetTester tester, DropZoneEvent event) async {
      events.add(event);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a drop with the caret mid-text inserts there with a space and keeps the rest', (
      tester,
    ) async {
      final chat = await pumpChat(tester);
      chat.textController.value = const TextEditingValue(
        text: 'read now',
        selection: TextSelection.collapsed(offset: 4),
      );

      await dropFiles(tester, <String>[p.join(root.path, 'notes.md')]);

      expect(chat.textController.text, 'read @notes.md now');
      // The caret goes past the space that follows the mention.
      expect(chat.textController.selection, const TextSelection.collapsed(offset: 15));
    });

    testWidgets('a drop just before a space adds no second one', (tester) async {
      final chat = await pumpChat(tester);
      chat.textController.value = const TextEditingValue(
        text: 'read  now',
        selection: TextSelection.collapsed(offset: 5),
      );

      await dropFiles(tester, <String>[p.join(root.path, 'notes.md')]);

      expect(chat.textController.text, 'read @notes.md now');
      // The caret goes past the space that follows the mention.
      expect(chat.textController.selection, const TextSelection.collapsed(offset: 15));
    });

    testWidgets('a drop glued to a word gets a space before it, several go in order', (
      tester,
    ) async {
      final chat = await pumpChat(tester);
      chat.textController.value = const TextEditingValue(
        text: 'compare',
        selection: TextSelection.collapsed(offset: 7),
      );
      final secret = p.join(outside.path, 'secret.txt');

      await dropFiles(tester, <String>[p.join(root.path, 'lib', 'main.dart'), secret]);

      expect(chat.textController.text, 'compare @lib/main.dart $secret ');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('dragging over the chat shows the drop hint until the drag leaves', (tester) async {
      await pumpChat(tester);
      expect(find.text('Drop files here'), findsNothing);
      final at = chatCenter(tester);

      await send(tester, DropZoneEvent$Enter(dx: at.dx, dy: at.dy));
      expect(find.text('Drop files here'), findsOneWidget);

      await send(tester, DropZoneEvent$Leave(dx: at.dx, dy: at.dy));
      expect(find.text('Drop files here'), findsNothing);
    });

    testWidgets('the drop hint goes away after the drop', (tester) async {
      await pumpChat(tester);
      final at = chatCenter(tester);
      await send(tester, DropZoneEvent$Enter(dx: at.dx, dy: at.dy));

      await dropFiles(tester, <String>[p.join(root.path, 'notes.md')]);

      expect(find.text('Drop files here'), findsNothing);
    });
  });
}
