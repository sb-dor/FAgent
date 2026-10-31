import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RunArguments.problem', () {
    test('is null for the default arguments', () {
      expect(const RunArguments().problem, isNull);
    });

    test('a define without "=" or with an empty key is a bad define', () {
      expect(const RunArguments(dartDefines: <String>['A']).problem, RunArgumentsProblem.badDefine);
      expect(
        const RunArguments(dartDefines: <String>['=1']).problem,
        RunArgumentsProblem.badDefine,
      );
      expect(
        const RunArguments(dartDefines: <String>['OK=1', 'B']).problem,
        RunArgumentsProblem.badDefine,
      );
    });

    test('a define with an empty value is fine', () {
      expect(const RunArguments(dartDefines: <String>['A=']).problem, isNull);
      expect(const RunArguments(dartDefines: <String>['A=b=c']).problem, isNull);
    });

    test('the flags the app sets itself are reserved', () {
      for (final flag in <String>[
        '-d macos',
        '--device-id macos',
        '--device-id=macos',
        '--machine',
        '-t lib/x.dart',
        '--target=x',
        '--debug',
        '--profile',
        '--release',
        '--flavor dev',
        '--flavor=dev',
        '--dart-define A=1',
        '--dart-define=A=1',
        'ok --release',
        '-dmacos',
        '-tlib/x.dart',
      ]) {
        expect(
          RunArguments(extraArgs: flag).problem,
          RunArgumentsProblem.reservedFlag,
          reason: flag,
        );
      }
    });

    test('--dart-define-from-file and other flags are allowed', () {
      expect(const RunArguments(extraArgs: '--dart-define-from-file=env.json').problem, isNull);
      expect(
        const RunArguments(extraArgs: '--dart-define-from-file env.json --verbose').problem,
        isNull,
      );
      expect(const RunArguments(extraArgs: '--no-sound-null-safety').problem, isNull);
    });

    test('an unclosed quote is unbalanced quotes', () {
      expect(const RunArguments(extraArgs: '"x').problem, RunArgumentsProblem.unbalancedQuotes);
    });
  });
}
