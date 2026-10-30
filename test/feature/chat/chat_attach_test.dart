import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/test_app.dart';

void main() {
  late Directory root;
  late Directory outside;
  late Dependencies dependencies;

  setUp(() {
    root = Directory.systemTemp.createTempSync('attach_project');
    outside = Directory.systemTemp.createTempSync('attach_outside');
    File(p.join(root.path, 'notes.md')).writeAsStringSync('notes');
    File(p.join(outside.path, 'secret.txt')).writeAsStringSync('secret');
    dependencies = testDependencies();
    addTearDown(() async {
      await dependencies.database.close();
      root.deleteSync(recursive: true);
      outside.deleteSync(recursive: true);
    });
  });

  Future<ChatConfigWidgetState> pumpChat(WidgetTester tester, String? picked) async {
    await tester.pumpWidget(
      testApp(
        dependencies: dependencies,
        ChatConfigWidget(
          sessionId: 404,
          project: Project(id: 1, path: root.path, name: 'p', isFlutter: false),
          pickFile: (_) async => picked,
        ),
      ),
    );
    return tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));
  }

  testWidgets('a file inside the project is mentioned at the caret', (tester) async {
    final chat = await pumpChat(tester, p.join(root.path, 'notes.md'));
    chat.textController.value = const TextEditingValue(
      text: 'read  now',
      selection: TextSelection.collapsed(offset: 5),
    );

    await tester.runAsync(chat.attachFile);
    await tester.pump();

    expect(chat.textController.text, 'read @notes.md  now');
    expect(chat.textController.selection, const TextSelection.collapsed(offset: 15));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a mention glued to a word gets a space before it', (tester) async {
    final chat = await pumpChat(tester, p.join(root.path, 'notes.md'));
    chat.textController.value = const TextEditingValue(
      text: 'read',
      selection: TextSelection.collapsed(offset: 4),
    );

    await tester.runAsync(chat.attachFile);

    expect(chat.textController.text, 'read @notes.md ');
  });

  testWidgets('a file outside the project is refused with a message', (tester) async {
    final chat = await pumpChat(tester, p.join(outside.path, 'secret.txt'));

    await tester.runAsync(chat.attachFile);
    await tester.pump();

    expect(chat.textController.text, isEmpty);
    expect(find.text('Only files inside the project can be attached'), findsOneWidget);
  });

  testWidgets('cancelling the dialog changes nothing', (tester) async {
    final chat = await pumpChat(tester, null);

    await tester.runAsync(chat.attachFile);
    await tester.pump();

    expect(chat.textController.text, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });
}
