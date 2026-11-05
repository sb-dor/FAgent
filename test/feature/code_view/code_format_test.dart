import 'dart:async';

import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_range.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import '../../support/memory_code_files_repository.dart';
import '../../support/memory_dart_analysis_repository.dart';

void main() {
  LspTextEdit edit(int line, int start, int end, String text, {int? endLine}) => LspTextEdit(
    range: LspRange(
      start: LspPosition(line: line, character: start),
      end: LspPosition(line: endLine ?? line, character: end),
    ),
    newText: text,
  );

  /// What the server answers for `void  main( ){}`: `void main() {}`.
  final mainEdits = <LspTextEdit>[edit(0, 4, 5, ''), edit(0, 11, 12, ''), edit(0, 13, 13, ' ')];

  CodeLineEditingController editing(String text) =>
      CodeLineEditingController(codeLines: CodeLines.fromText(text));

  group('applyTextEdits', () {
    test('applies edits bottom-up and keeps the caret on the same code', () {
      final controller = editing('void  main( ){}\n')
        ..selection = const CodeLineSelection.collapsed(index: 0, offset: 6);

      applyTextEdits(controller, mainEdits);

      expect(controller.text, 'void main() {}\n');
      expect(controller.selection, const CodeLineSelection.collapsed(index: 0, offset: 5));
    });

    test('one undo restores the unformatted text', () {
      final controller = editing('void  main( ){}\n');

      applyTextEdits(controller, mainEdits);
      controller.undo();

      expect(controller.text, 'void  main( ){}\n');
    });

    test('an edit across lines and a caret below it', () {
      final controller = editing('a(\n  1,\n);\nb;\n')
        ..selection = const CodeLineSelection.collapsed(index: 3, offset: 1);

      applyTextEdits(controller, <LspTextEdit>[edit(0, 2, 0, '1', endLine: 2)]);

      expect(controller.text, 'a(1);\nb;\n');
      expect(controller.selection, const CodeLineSelection.collapsed(index: 1, offset: 1));
    });

    test('a CRLF file keeps CRLF', () {
      final controller = CodeLineEditingController(
        codeLines: CodeLines.fromText('a  =  1;\r\nb;\r\n'),
        options: const CodeLineOptions(lineBreak: TextLineBreak.crlf),
      );

      applyTextEdits(controller, <LspTextEdit>[edit(0, 1, 3, ' '), edit(0, 4, 6, ' ')]);

      expect(controller.text, 'a = 1;\r\nb;\r\n');
      expect(controller.options.lineBreak, TextLineBreak.crlf);
    });

    test('a folded block is opened first, so lines are document lines', () {
      final controller = editing('void a() {\n  1;\n  2;\n}\nvoid  b() {}\n')..collapseChunk(0, 3);

      applyTextEdits(controller, <LspTextEdit>[edit(4, 4, 6, ' ')]);

      expect(controller.text, 'void a() {\n  1;\n  2;\n}\nvoid b() {}\n');
    });
  });

  group('formatDocument', () {
    const path = '/p/lib/main.dart';
    late MemoryCodeFilesRepository files;
    late MemoryDartAnalysisRepository analysis;

    setUp(() {
      files = MemoryCodeFilesRepository(
        files: <String, String>{
          path: 'void  main( ){}\n',
          '/p/README.md': 'a  b\n',
          '/sdk/lib/a.dart': 'void  main( ){}\n',
        },
      );
      analysis = MemoryDartAnalysisRepository()..onFormat = (path, text) => mainEdits;
    });

    test('formats a Dart document', () async {
      final document = await CodeDocument.open(path, files: files);
      addTearDown(document.dispose);

      expect(await formatDocument(document, analysis), isTrue);
      expect(document.editing.text, 'void main() {}\n');
    });

    test('drops the answer when the text changed meanwhile', () async {
      final answer = Completer<List<LspTextEdit>?>();
      analysis.onFormat = (path, text) => answer.future;
      final document = await CodeDocument.open(path, files: files);
      addTearDown(document.dispose);

      final formatting = formatDocument(document, analysis);
      document.editing.replaceSelection('// ');
      answer.complete(mainEdits);

      expect(await formatting, isFalse);
      expect(document.editing.text, '// void  main( ){}\n');
    });

    test('an empty or null answer changes nothing', () async {
      final document = await CodeDocument.open(path, files: files);
      addTearDown(document.dispose);
      analysis.onFormat = (path, text) => null;
      expect(await formatDocument(document, analysis), isFalse);
      analysis.onFormat = (path, text) => const <LspTextEdit>[];
      expect(await formatDocument(document, analysis), isFalse);
      expect(document.editing.canUndo, isFalse);
    });

    test('read-only and non-Dart documents are not formatted', () async {
      final readOnly = await CodeDocument.open('/sdk/lib/a.dart', files: files, readOnly: true);
      final markdown = await CodeDocument.open('/p/README.md', files: files);
      addTearDown(readOnly.dispose);
      addTearDown(markdown.dispose);

      expect(await formatDocument(readOnly, analysis), isFalse);
      expect(await formatDocument(markdown, analysis), isFalse);
      expect(readOnly.editing.text, 'void  main( ){}\n');
    });
  });
}
