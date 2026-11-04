import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_completion.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/completion_edit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  CodeLineEditingController editor(String text, {required int line, required int column}) =>
      CodeLineEditingController.fromText(text)
        ..selection = CodeLineSelection.collapsed(index: line, offset: column);

  DartCompletion plain(String text, {LspTextEdit? edit, List<LspTextEdit> more = const <LspTextEdit>[]}) =>
      DartCompletion(
        label: text,
        kind: DartCompletionKind.classType,
        insertText: text,
        edit: edit,
        additionalEdits: more,
      );

  LspRange range(int line, int start, [int? end, int? endLine]) => LspRange(
    start: LspPosition(line: line, character: start),
    end: LspPosition(line: endLine ?? line, character: end ?? start),
  );

  test('a plain completion replaces the word before the caret', () {
    final editing = editor('final x = Str;', line: 0, column: 13);

    final session = applyCompletion(
      editing,
      plain('String'),
      caret: const LspPosition(line: 0, character: 13),
    );

    expect(editing.text, 'final x = String;');
    expect(editing.selection, const CodeLineSelection.collapsed(index: 0, offset: 16));
    expect(session, isNull);
  });

  test('a completion with a textEdit replaces exactly its range', () {
    final editing = editor('foo.ba', line: 0, column: 6);

    applyCompletion(
      editing,
      plain('bar()', edit: LspTextEdit(range: range(0, 4, 6), newText: 'bar()')),
      caret: const LspPosition(line: 0, character: 6),
    );

    expect(editing.text, 'foo.bar()');
  });

  test('an import added above shifts the main edit and the caret down one line', () {
    final editing = editor('void main() {\n  Uu\n}', line: 1, column: 4);

    applyCompletion(
      editing,
      plain(
        'Uuid',
        more: <LspTextEdit>[
          LspTextEdit(range: range(0, 0), newText: "import 'package:uuid/uuid.dart';\n\n"),
        ],
      ),
      caret: const LspPosition(line: 1, character: 4),
    );

    expect(editing.text, "import 'package:uuid/uuid.dart';\n\nvoid main() {\n  Uuid\n}");
    expect(editing.selection, const CodeLineSelection.collapsed(index: 3, offset: 6));
  });

  test('a line with an emoji and a tab inserts at the UTF-16 column', () {
    // '👋' is two UTF-16 units: the word `fo` ends at column 5.
    final editing = editor('👋\tfo = 1;', line: 0, column: 5);

    applyCompletion(editing, plain('foo'), caret: const LspPosition(line: 0, character: 5));

    expect(editing.text, '👋\tfoo = 1;');
  });

  test('a snippet is indented like its line and starts a session on its first stop', () {
    final editing = editor('class A {\n  st\n}', line: 1, column: 4);

    final session = applyCompletion(
      editing,
      const DartCompletion(
        label: 'stful',
        kind: DartCompletionKind.snippet,
        isSnippet: true,
        insertText: 'void \${1:name}() {\n  \$0\n}',
      ),
      caret: const LspPosition(line: 1, character: 4),
    );

    expect(editing.text, 'class A {\n  void name() {\n    \n  }\n}');
    expect(editing.selectedText, 'name');
    expect(session?.active, isTrue);
  });
}
