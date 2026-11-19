import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_completion.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DartCompletion.fromJson', () {
    test('an item whose label is not a string is skipped', () {
      expect(DartCompletion.fromJson(<String, Object?>{'label': 1}), isNull);
      expect(DartCompletion.fromJson('x'), isNull);
    });

    test('a field of the wrong type is ignored, the item is kept', () {
      final completion = DartCompletion.fromJson(<String, Object?>{
        'label': 'ok',
        'kind': 3,
        'detail': 5,
        'sortText': <Object?>[],
        'additionalTextEdits': <Object?>[
          <String, Object?>{'range': 'x', 'newText': 1},
          <String, Object?>{
            'range': <String, Object?>{
              'start': <String, Object?>{'line': 1, 'character': 2},
              'end': <String, Object?>{'line': 1, 'character': 3},
            },
            'newText': 'import "a";',
          },
        ],
      });

      expect(completion?.label, 'ok');
      expect(completion?.kind, DartCompletionKind.function);
      expect(completion?.detail, isNull);
      expect(completion?.sortText, isNull);
      expect(completion?.additionalEdits.map((e) => e.newText), <String>['import "a";']);
    });
  });

  group('DartDiagnostic.fromJson', () {
    Map<String, Object?> range(Object? line) => <String, Object?>{
      'start': <String, Object?>{'line': line, 'character': 0},
      'end': <String, Object?>{'line': line, 'character': 4},
    };

    test('an item with a non-numeric line is skipped', () {
      expect(
        DartDiagnostic.fromJson(<String, Object?>{'range': range('x'), 'message': 'm'}),
        isNull,
      );
    });

    test('a well-formed item parses and a bad severity falls back to error', () {
      final diagnostic = DartDiagnostic.fromJson(<String, Object?>{
        'range': range(3),
        'severity': 'warning',
        'message': 'm',
        'code': 'c',
      });

      expect(diagnostic?.range.start.line, 3);
      expect(diagnostic?.severity, DartSeverity.error);
      expect(diagnostic?.message, 'm');
    });
  });

  test('a range without a numeric character is not a range', () {
    expect(
      LspRange.fromJson(<String, Object?>{
        'start': <String, Object?>{'line': 1, 'character': 'x'},
        'end': <String, Object?>{'line': 1, 'character': 2},
      }),
      isNull,
    );
  });
}
