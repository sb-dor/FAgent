import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/feature/chat/models/drop_classification.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
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

  group('the chat', () {
    late Dependencies dependencies;

    setUp(() {
      dependencies = testDependencies();
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

    DropTarget target(WidgetTester tester) => tester.widget<DropTarget>(find.byType(DropTarget));

    Future<void> dropFiles(WidgetTester tester, List<String> paths) async {
      await tester.runAsync(() async {
        target(tester).onDragDone!(
          DropDoneDetails(
            files: <DropItem>[for (final path in paths) DropItemFile(path)],
            localPosition: Offset.zero,
            globalPosition: Offset.zero,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
    }

    testWidgets('a drop with the caret mid-text inserts there with a space and keeps the rest', (
      tester,
    ) async {
      final chat = await pumpChat(tester);
      chat.textController.value = const TextEditingValue(
        text: 'read  now',
        selection: TextSelection.collapsed(offset: 5),
      );

      await dropFiles(tester, <String>[p.join(root.path, 'notes.md')]);

      expect(chat.textController.text, 'read @notes.md  now');
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
      expect(find.text('Release to attach'), findsNothing);

      target(tester).onDragEntered!(
        DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero),
      );
      await tester.pump();
      expect(find.text('Release to attach'), findsOneWidget);

      target(tester)
          .onDragExited!(DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero));
      await tester.pump();
      expect(find.text('Release to attach'), findsNothing);
    });

    testWidgets('the drop hint goes away after the drop', (tester) async {
      await pumpChat(tester);
      target(tester).onDragEntered!(
        DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero),
      );
      await tester.pump();

      await dropFiles(tester, <String>[p.join(root.path, 'notes.md')]);

      expect(find.text('Release to attach'), findsNothing);
    });
  });
}
