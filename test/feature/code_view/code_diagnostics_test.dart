import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_diagnostic.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_workspace.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/dart_analysis_repository.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_analysis_footer.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_diagnostic_spans.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_explorer.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_tab_bar.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import '../../support/memory_code_files_repository.dart';
import '../../support/memory_code_view_state_repository.dart';
import '../../support/memory_dart_analysis_repository.dart';
import '../../support/test_app.dart';

DartDiagnostic _diagnostic(
  DartSeverity severity, {
  int line = 0,
  required int start,
  required int end,
  int? endLine,
  String message = 'Undefined name',
  String? code = 'undefined_identifier',
}) => DartDiagnostic(
  range: LspRange(
    start: LspPosition(line: line, character: start),
    end: LspPosition(line: endLine ?? line, character: end),
  ),
  severity: severity,
  message: message,
  code: code,
);

/// The leaf spans of [span] as (text, decoration color).
List<(String, Color?)> _leaves(InlineSpan span) {
  final leaves = <(String, Color?)>[];
  void visit(InlineSpan span, TextStyle? inherited) {
    if (span is! TextSpan) return;
    final style = inherited?.merge(span.style) ?? span.style;
    if (span.text case final text? when text.isNotEmpty) {
      leaves.add((
        text,
        style?.decoration == TextDecoration.underline ? style?.decorationColor : null,
      ));
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, style);
    }
  }

  visit(span, null);
  return leaves;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const colors = AppColors.light;
  const keyword = TextStyle(color: Color(0xFF000001));
  const name = TextStyle(color: Color(0xFF000002));
  const line = TextSpan(
    children: <InlineSpan>[
      TextSpan(text: 'void ', style: keyword),
      TextSpan(text: 'main', style: name),
      TextSpan(text: '() {}'),
    ],
  );

  group('diagnosticSpans', () {
    TextSpan spans(List<DartDiagnostic> diagnostics, {int index = 0, TextSpan span = line}) =>
        diagnosticSpans(textSpan: span, line: index, diagnostics: diagnostics, colors: colors);

    test('an error, a warning and a hint are underlined in danger, warn and muted', () {
      final result = spans(<DartDiagnostic>[
        _diagnostic(DartSeverity.error, start: 0, end: 4),
        _diagnostic(DartSeverity.warning, start: 5, end: 9),
        _diagnostic(DartSeverity.hint, start: 9, end: 11),
      ]);

      expect(_leaves(result), <(String, Color?)>[
        ('void', colors.danger),
        (' ', null),
        ('main', colors.warn),
        ('()', colors.muted),
        (' {}', null),
      ]);
    });

    test('the underline is wavy and text outside the ranges keeps its highlight style', () {
      final result = spans(<DartDiagnostic>[_diagnostic(DartSeverity.error, start: 5, end: 9)]);
      final styles = <String, TextStyle?>{};
      void visit(InlineSpan span, TextStyle? inherited) {
        if (span is! TextSpan) return;
        final style = inherited?.merge(span.style) ?? span.style;
        if (span.text case final text?) styles[text] = style;
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, style);
        }
      }

      visit(result, null);
      expect(styles['void ']?.color, keyword.color);
      expect(styles['main']?.color, name.color);
      expect(styles['main']?.decorationStyle, TextDecorationStyle.wavy);
    });

    test('a multi-line range underlines each line part', () {
      final diagnostic = _diagnostic(DartSeverity.error, start: 7, end: 2, endLine: 2);

      expect(
        _leaves(spans(<DartDiagnostic>[diagnostic], index: 1)).map((leaf) => leaf.$2),
        everyElement(colors.danger),
      );
      expect(_leaves(spans(<DartDiagnostic>[diagnostic], index: 2)), <(String, Color?)>[
        ('vo', colors.danger),
        ('id ', null),
        ('main', null),
        ('() {}', null),
      ]);
      expect(_leaves(spans(<DartDiagnostic>[diagnostic], index: 0)), <(String, Color?)>[
        ('void ', null),
        ('ma', null),
        ('in', colors.danger),
        ('() {}', colors.danger),
      ]);
    });

    test('a line without diagnostics is the same span', () {
      expect(spans(const <DartDiagnostic>[]), same(line));
    });
  });

  group('in the Code view', () {
    const root = '/p';
    const main = '$root/lib/main.dart';
    late MemoryCodeFilesRepository files;
    late MemoryDartAnalysisRepository analysis;
    late CodeWorkspace workspace;

    setUp(() {
      files = MemoryCodeFilesRepository(
        files: <String, String>{main: 'void main() { x; }\n', '$root/lib/other.dart': '\n'},
      );
      analysis = MemoryDartAnalysisRepository();
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
          CodeView(
            workspace: workspace,
            onOpenExternally: (_) {},
            listFiles: () async => <String>[],
          ),
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

    void publish(String path, List<DartDiagnostic> diagnostics) =>
        analysis.push(DartFileDiagnostics(path, diagnostics));

    testCode('published diagnostics reach the document and its line spans', (tester) async {
      final document = await pump(tester);

      publish(main, <DartDiagnostic>[_diagnostic(DartSeverity.error, start: 14, end: 15)]);
      await settle(tester);

      expect(document.diagnostics.value, hasLength(1));
      final context = tester.element(find.byType(CodeEditor));
      final span = document.decorator!(
        context: context,
        index: 0,
        codeLine: document.editing.codeLines[0],
        textSpan: const TextSpan(text: 'void main() { x; }'),
        style: const TextStyle(),
      );
      expect(_leaves(span), contains(('x', context.colors.danger)));
    });

    testCode('C1: with a fold above, a line is underlined by its real line', (tester) async {
      files.put(main, 'void a() {\n  x;\n}\ny;\n', notify: false);
      final document = await pump(tester);
      publish(main, <DartDiagnostic>[_diagnostic(DartSeverity.error, line: 3, start: 0, end: 1)]);
      await settle(tester);
      document.editing.collapseChunk(0, 3);
      await tester.pump();
      final context = tester.element(find.byType(CodeEditor));

      final span = document.decorator!(
        context: context,
        index: 1,
        codeLine: document.editing.codeLines[1],
        textSpan: const TextSpan(text: 'y;'),
        style: const TextStyle(),
      );

      expect(_leaves(span), contains(('y', context.colors.danger)));
    });

    testCode('the tab shows ⓧ 2 ⚠ 1', (tester) async {
      await pump(tester);

      publish(main, <DartDiagnostic>[
        _diagnostic(DartSeverity.error, start: 0, end: 1),
        _diagnostic(DartSeverity.error, start: 2, end: 3),
        _diagnostic(DartSeverity.warning, start: 4, end: 5),
        _diagnostic(DartSeverity.hint, start: 6, end: 7),
      ]);
      await settle(tester);

      expect(
        find.descendant(of: find.byType(CodeTabBar), matching: find.text('ⓧ 2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(CodeTabBar), matching: find.text('⚠ 1')),
        findsOneWidget,
      );
    });

    testCode('the explorer shows a file with errors in danger, and not once they are gone', (
      tester,
    ) async {
      await pump(tester);
      workspace.tree.toggle('$root/lib');
      await settle(tester);
      Color? colorOf(String name) => tester
          .widget<Text>(find.descendant(of: find.byType(CodeExplorer), matching: find.text(name)))
          .style
          ?.color;
      final context = tester.element(find.byType(CodeExplorer));

      publish('$root/lib/other.dart', <DartDiagnostic>[
        _diagnostic(DartSeverity.error, start: 0, end: 1),
      ]);
      await settle(tester);
      expect(colorOf('other.dart'), context.colors.danger);
      expect(colorOf('main.dart'), context.colors.text);

      publish('$root/lib/other.dart', const <DartDiagnostic>[]);
      await settle(tester);
      expect(colorOf('other.dart'), context.colors.text);
    });

    testCode('a reopened tab gets the diagnostics published before', (tester) async {
      await pump(tester);
      publish(main, <DartDiagnostic>[_diagnostic(DartSeverity.error, start: 0, end: 1)]);
      await settle(tester);

      workspace.tabs.close(main);
      await settle(tester);
      final again = (await tester.runAsync(() => workspace.tabs.open(main)))!;
      await settle(tester);

      expect(again.diagnostics.value, hasLength(1));
    });

    testCode('the footer says Analyzing… while starting and analyzing, nothing when ready', (
      tester,
    ) async {
      await pump(tester);

      analysis.status.value = const DartAnalysisStatus.starting();
      await tester.pump();
      expect(find.text('Analyzing…'), findsOneWidget);

      analysis.status.value = const DartAnalysisStatus.analyzing();
      await tester.pump();
      expect(find.text('Analyzing…'), findsOneWidget);

      analysis.status.value = const DartAnalysisStatus.ready();
      await tester.pump();
      expect(find.byType(CodeAnalysisFooter), findsOneWidget);
      expect(find.text('Analyzing…'), findsNothing);
    });

    testCode('unavailable shows the line and Restart restarts', (tester) async {
      await pump(tester);

      analysis.status.value = const DartAnalysisStatus.unavailable(reason: 'dart not found');
      await tester.pump();

      expect(find.text('Dart analysis unavailable'), findsOneWidget);
      expect(find.text('dart not found'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pump();
      expect(analysis.restarts, 1);
    });

    for (final locale in const <Locale>[Locale('en'), Locale('ru')]) {
      for (final dark in const <bool>[false, true]) {
        testCode('the footer and counts fit at 900×600 in ${locale.languageCode}, '
            '${dark ? 'dark' : 'light'}', (tester) async {
          await pump(tester, size: const Size(900, 600), locale: locale, dark: dark);
          publish(main, <DartDiagnostic>[
            _diagnostic(DartSeverity.error, start: 0, end: 1),
            _diagnostic(DartSeverity.warning, start: 2, end: 3),
          ]);
          analysis.status.value = const DartAnalysisStatus.unavailable(
            reason:
                'ProcessException: No such file or directory, the command was dart language-server',
          );
          await settle(tester);

          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
