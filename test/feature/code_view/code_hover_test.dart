import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_diagnostic.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_hover.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_workspace.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_editor_view.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_hover_card.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import '../../support/memory_code_files_repository.dart';
import '../../support/memory_code_view_state_repository.dart';
import '../../support/memory_dart_analysis_repository.dart';
import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const root = '/p';
  const main = '$root/lib/main.dart';
  const hoverText = '```dart\nclass Foo\n```\nA foo.';
  late MemoryCodeFilesRepository files;
  late MemoryDartAnalysisRepository analysis;
  late CodeWorkspace workspace;
  late List<LspPosition> asked;

  setUp(() {
    files = MemoryCodeFilesRepository(
      files: <String, String>{main: 'void main() {\n  Foo x;\n}\n'},
    );
    asked = <LspPosition>[];
    analysis = MemoryDartAnalysisRepository()
      ..onHover = (path, text, position) {
        asked.add(position);
        return const DartHover(markdown: hoverText);
      };
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<CodeDocument> pump(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    Locale locale = const Locale('en'),
    bool dark = false,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    workspace = CodeWorkspace(
      projectId: 1,
      root: root,
      files: files,
      state: MemoryCodeViewStateRepository(),
      analysis: analysis,
    );
    await tester.pumpWidget(
      testApp(
        CodeView(workspace: workspace, onOpenExternally: (_) {}, listFiles: () async => <String>[]),
        locale: locale,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
      ),
    );
    final document = (await tester.runAsync(() => workspace.tabs.open(main)))!;
    await settle(tester);
    return document;
  }

  void testCode(String description, Future<void> Function(WidgetTester tester) body) =>
      testWidgets(description, (tester) async {
        await body(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        workspace.dispose();
        await tester.pump(const Duration(seconds: 1));
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  /// The global middle of [column] on [line] (no scroll, no fold).
  Offset charAt(WidgetTester tester, int line, int column) {
    const style = TextStyle(
      fontFamily: AppText.monoFamily,
      fontSize: CodeEditorView.fontSize,
      height: CodeEditorView.lineHeight,
    );
    final painter = TextPainter(
      text: const TextSpan(text: 'M', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final editor = tester.getTopLeft(find.byType(CodeEditor));
    final gutter = tester.getTopRight(find.byType(DefaultCodeChunkIndicator)).dx;
    return Offset(
      gutter + CodeEditorView.padding + column * painter.width + painter.width / 2,
      editor.dy + CodeEditorView.padding + line * painter.height + painter.height / 2,
    );
  }

  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    return gesture;
  }

  /// Rests the pointer on `Foo` (line 1, column 3) past the hover delay.
  Future<TestGesture> restOnFoo(WidgetTester tester) async {
    final gesture = await mouse(tester);
    await gesture.moveTo(charAt(tester, 1, 3));
    await tester.pump(const Duration(milliseconds: 550));
    await settle(tester);
    return gesture;
  }

  testCode('resting 500 ms on a name shows its declaration and docs', (tester) async {
    await pump(tester);
    final gesture = await mouse(tester);

    await gesture.moveTo(charAt(tester, 1, 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CodeHoverCard), findsNothing);

    await tester.pump(const Duration(milliseconds: 250));
    await settle(tester);
    expect(asked, <LspPosition>[const LspPosition(line: 1, character: 3)]);
    expect(find.byType(CodeHoverCard), findsOneWidget);
    expect(find.text('class Foo'), findsOneWidget);
    expect(find.text('A foo.'), findsOneWidget);
  });

  testCode('an error under the pointer shows in the same card', (tester) async {
    await pump(tester);
    analysis.push(
      const DartFileDiagnostics(main, <DartDiagnostic>[
        DartDiagnostic(
          range: LspRange(
            start: LspPosition(line: 1, character: 2),
            end: LspPosition(line: 1, character: 5),
          ),
          severity: DartSeverity.error,
          message: "Undefined class 'Foo'.",
          code: 'undefined_class',
        ),
      ]),
    );
    await settle(tester);

    await restOnFoo(tester);

    expect(find.byType(CodeHoverCard), findsOneWidget);
    expect(find.text("Undefined class 'Foo'. (undefined_class)"), findsOneWidget);
    expect(find.text('A foo.'), findsOneWidget);
  });

  testCode('an error alone shows without hover docs', (tester) async {
    analysis.onHover = null;
    await pump(tester);
    analysis.push(
      const DartFileDiagnostics(main, <DartDiagnostic>[
        DartDiagnostic(
          range: LspRange(
            start: LspPosition(line: 1, character: 2),
            end: LspPosition(line: 1, character: 5),
          ),
          severity: DartSeverity.error,
          message: 'Boom.',
        ),
      ]),
    );
    await settle(tester);

    await restOnFoo(tester);

    expect(find.text('Boom.'), findsOneWidget);
  });

  testCode('typing or Esc closes the card', (tester) async {
    final document = await pump(tester);
    final gesture = await restOnFoo(tester);
    expect(find.byType(CodeHoverCard), findsOneWidget);

    document.editing.replaceSelection('x');
    await tester.pump();
    expect(find.byType(CodeHoverCard), findsNothing);

    await tester.tap(find.byType(CodeEditor), warnIfMissed: false);
    await tester.pump();
    await gesture.moveTo(charAt(tester, 1, 4));
    await tester.pump(const Duration(milliseconds: 550));
    await settle(tester);
    expect(find.byType(CodeHoverCard), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(CodeHoverCard), findsNothing);
  });

  testCode('a hover answer after an edit is dropped', (tester) async {
    final answer = Completer<DartHover?>();
    analysis.onHover = (path, text, position) => answer.future;
    final document = await pump(tester);
    final gesture = await mouse(tester);
    await gesture.moveTo(charAt(tester, 1, 3));
    await tester.pump(const Duration(milliseconds: 550));

    document.editing.replaceSelection('x');
    answer.complete(const DartHover(markdown: hoverText));
    await settle(tester);

    expect(find.byType(CodeHoverCard), findsNothing);
  });

  testCode('moving into the card keeps it open; leaving both closes it', (tester) async {
    await pump(tester);
    final gesture = await restOnFoo(tester);

    await gesture.moveTo(tester.getCenter(find.text('A foo.')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CodeHoverCard), findsOneWidget);

    await gesture.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CodeHoverCard), findsNothing);
  });

  for (final locale in const <Locale>[Locale('en'), Locale('ru')]) {
    for (final dark in <bool>[false, true]) {
      testCode('the card fits at 900×600 in ${locale.languageCode}, '
          '${dark ? 'dark' : 'light'}', (tester) async {
        analysis.onHover = (path, text, position) =>
            DartHover(markdown: '```dart\nclass Foo\n```\n${'Long docs. ' * 200}');
        await pump(tester, size: const Size(900, 600), locale: locale, dark: dark);

        await restOnFoo(tester);

        expect(find.byType(CodeHoverCard), findsOneWidget);
        expect(tester.getSize(find.byType(CodeHoverCard)).height, lessThanOrEqualTo(300));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
