import 'package:flutter_code_agent/src/feature/code_view/controller/snippet_session.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/snippet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  const stful =
      r'class ${1:MyWidget} extends StatefulWidget {'
      '\n'
      r'  const ${1:MyWidget}({super.key});'
      '\n'
      '}\n'
      '\n'
      r'class _${1:MyWidget}State extends State<${1:MyWidget}> {'
      '\n'
      r'  ${0:// body}'
      '\n'
      '}';

  group('parse', () {
    test(r'reads $1, ${1:name}, ${1|a,b|}, $0 and escapes', () {
      final snippet = Snippet.parse(r'a $1 ${2:name} ${3|x,y|} \$5 \} $0');

      expect(snippet.text, r'a  name x $5 } ');
      expect(snippet.stops.map((stop) => stop.index), <int>[1, 2, 3, 0]);
      expect(snippet.stops[0].offsets, <(int, int)>[(2, 2)]);
      expect(snippet.stops[1].offsets, <(int, int)>[(3, 7)]);
      expect(snippet.stops[2].offsets, <(int, int)>[(8, 9)]);
      expect(snippet.stops[3].offsets, <(int, int)>[(15, 15)]);
    });

    test('placeholders with the same index are one stop with mirrors', () {
      final snippet = Snippet.parse(stful);

      expect(snippet.stops.first.index, 1);
      expect(snippet.stops.first.offsets, hasLength(4));
      expect(snippet.text, contains('class _MyWidgetState extends State<MyWidget>'));
    });

    test('a snippet without stops ends at its end', () {
      final snippet = Snippet.parse('plain');

      expect(snippet.stops.single.index, 0);
      expect(snippet.stops.single.offsets, <(int, int)>[(5, 5)]);
    });

    test('indented adds the line indent after every newline and shifts the stops', () {
      final snippet = Snippet.parse('a\n\$1b').indented('  ');

      expect(snippet.text, 'a\n  b');
      expect(snippet.stops.first.offsets, <(int, int)>[(4, 4)]);
    });
  });

  group('session', () {
    late CodeLineEditingController editing;

    SnippetSession start(String body, {String text = '', int line = 0, int column = 0}) {
      editing = CodeLineEditingController.fromText(text);
      final snippet = Snippet.parse(body);
      editing
        ..selection = CodeLineSelection.collapsed(index: line, offset: column)
        ..replaceSelection(snippet.text);
      return SnippetSession(editing, line: line, column: column, snippet: snippet);
    }

    test('the stful body selects the widget name first; typing renames the State class too', () {
      final session = start(stful);

      expect(editing.selectedText, 'MyWidget');
      editing.replaceSelection('Counter');
      session.onEdit();

      expect(editing.text, contains('class Counter extends StatefulWidget {'));
      expect(editing.text, contains('const Counter({super.key});'));
      expect(editing.text, contains('class _CounterState extends State<Counter> {'));
      expect(session.active, isTrue);
    });

    test('Tab goes 1 → 2 → 0 and then ends; ⇧Tab goes back', () {
      final session = start(r'${1:a} ${2:b} $0');

      expect(editing.selectedText, 'a');
      expect(session.next(), isTrue);
      expect(editing.selectedText, 'b');
      expect(session.previous(), isTrue);
      expect(editing.selectedText, 'a');
      expect(session.next(), isTrue);
      expect(session.next(), isTrue);
      expect(editing.selection, const CodeLineSelection.collapsed(index: 0, offset: 4));
      expect(session.active, isFalse);
      expect(session.next(), isFalse);
    });

    test('an edit before a later stop shifts it', () {
      final session = start(r'${1:a} ${2:b}');

      editing.replaceSelection('longer');
      session
        ..onEdit()
        ..next();

      expect(editing.selectedText, 'b');
    });

    test('the caret leaving the snippet ends it', () {
      final session = start(r'${1:a} ${2:b}', text: '\nafter');

      editing.selection = const CodeLineSelection.collapsed(index: 1, offset: 3);
      session.onEdit();

      expect(session.active, isFalse);
    });

    test('end stops it', () {
      final session = start(r'${1:a}')..end();

      expect(session.active, isFalse);
      expect(session.next(), isFalse);
    });
  });
}
