import 'dart:io';

import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/run_mentions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/test_app.dart';

void main() {
  const shot = '.dart_tool/flutter_code_agent/screenshots/screenshot-20261031-090507.png';
  late Directory root;
  late Dependencies dependencies;

  setUp(() {
    root = Directory.systemTemp.createTempSync('run_attachment_project');
    File(p.join(root.path, 'notes.md')).writeAsStringSync('notes');
    File(p.join(root.path, shot))
      ..createSync(recursive: true)
      ..writeAsBytesSync(<int>[0x89, 0x50, 0x4e, 0x47]);
    dependencies = testDependencies();
    addTearDown(() async {
      await dependencies.database.close();
      root.deleteSync(recursive: true);
    });
  });

  Future<ChatConfigWidgetState> pumpChat(WidgetTester tester, {RunMentions? runContext}) async {
    await tester.pumpWidget(
      testApp(
        dependencies: dependencies,
        ChatConfigWidget(
          sessionId: 404,
          project: Project(id: 1, path: root.path, name: 'p', isFlutter: false),
          runContext: runContext,
        ),
      ),
    );
    return tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));
  }

  Future<List<Map<String, Object?>>> resources(
    WidgetTester tester,
    ChatConfigWidgetState chat,
    String text,
  ) async {
    late List<Map<String, Object?>> found;
    await tester.runAsync(() async => found = await chat.resourcesFor(text));
    return found;
  }

  const offer = RunMentions(
    screenshot: RunMention(detail: '09:05:07', text: '@$shot'),
    attachable: <String>{shot},
  );

  testWidgets('a mentioned screenshot of the run becomes a resource_link to its file', (
    tester,
  ) async {
    final chat = await pumpChat(tester, runContext: offer);

    final found = await resources(tester, chat, 'what is wrong here? @$shot');

    expect(found, <Map<String, Object?>>[
      <String, Object?>{
        'type': 'resource_link',
        'uri': Uri.file(p.join(root.path, shot)).toString(),
        'name': 'screenshot-20261031-090507.png',
      },
    ]);
  });

  testWidgets('a screenshot of an older run is still attached when the user mentions it', (
    tester,
  ) async {
    final chat = await pumpChat(
      tester,
      runContext: const RunMentions(
        screenshot: RunMention(detail: '09:09:09', text: '@.dart_tool/other.png'),
        attachable: <String>{shot, '.dart_tool/other.png'},
      ),
    );

    final found = await resources(tester, chat, '@$shot and @notes.md');

    expect(found.map((link) => link['name']), <String>['screenshot-20261031-090507.png']);
  });

  testWidgets('without the offer the same path is plain text', (tester) async {
    final chat = await pumpChat(tester);

    expect(await resources(tester, chat, '@$shot'), isEmpty);
  });

  testWidgets('a screenshot that was deleted is not attached', (tester) async {
    final chat = await pumpChat(tester, runContext: offer);
    File(p.join(root.path, shot)).deleteSync();

    expect(await resources(tester, chat, '@$shot'), isEmpty);
  });

  testWidgets('project files are attached as before', (tester) async {
    final chat = await pumpChat(tester, runContext: offer);
    await tester.runAsync(() async {
      chat.fileMentionController.load(root.path);
      for (var i = 0; i < 100 && chat.fileMentionController.files.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    expect(chat.fileMentionController.files, contains('notes.md'));

    final found = await resources(tester, chat, 'see @notes.md and @$shot');

    expect(found.map((link) => link['name']), <String>[
      'notes.md',
      'screenshot-20261031-090507.png',
    ]);
  });
}
