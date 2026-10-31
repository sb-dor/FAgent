import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitArguments', () {
    test('splits on spaces and keeps quoted text together', () {
      expect(splitArguments('-y "@figma/mcp" --stdio'), <String>['-y', '@figma/mcp', '--stdio']);
      expect(splitArguments('--path "/My Files/x" b'), <String>['--path', '/My Files/x', 'b']);
    });

    test('ignores extra whitespace and keeps an empty quoted argument', () {
      expect(splitArguments('  a \t  b  '), <String>['a', 'b']);
      expect(splitArguments('a "" b'), <String>['a', '', 'b']);
      expect(splitArguments('   '), isEmpty);
    });

    test('joins quoted and plain parts of one argument', () {
      expect(splitArguments('--name="a b"'), <String>['--name=a b']);
    });

    test('an unclosed quote takes the rest of the line', () {
      expect(splitArguments('a "b c'), <String>['a', 'b c']);
    });
  });

  group('parseKeyValueLines', () {
    test('reads KEY=VALUE lines, skipping blanks', () {
      expect(parseKeyValueLines('A=1\n\n B = two=2 \r\nC=', '='), <String, String>{
        'A': '1',
        'B': 'two=2',
        'C': '',
      });
    });

    test('reads Name: value lines', () {
      expect(parseKeyValueLines('Authorization: Bearer x\nX-A:b', ':'), <String, String>{
        'Authorization': 'Bearer x',
        'X-A': 'b',
      });
    });

    test('a line without the separator or a key is refused', () {
      expect(parseKeyValueLines('nothing here', '='), isNull);
      expect(parseKeyValueLines('=value', '='), isNull);
      expect(parseKeyValueLines('A=1\nbad', '='), isNull);
    });

    test('empty text is an empty map', () {
      expect(parseKeyValueLines('  \n ', '='), isEmpty);
    });
  });
}
