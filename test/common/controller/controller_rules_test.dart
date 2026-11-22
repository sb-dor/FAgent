import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The controller recipe: errors reach the observer through `handle(error:, done:)`.
///
/// A controller catches nothing wholesale (`on Object`, an untyped `catch`) and has no `finally`;
/// a side read that the screen can do without catches `on Exception` and reports through
/// `ErrorUtil.logError` right after.
void main() {
  final controllers = Directory('lib/src')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('_controller.dart'))
      .toList();

  test('there are controllers to check', () => expect(controllers, isNotEmpty));

  for (final file in controllers) {
    test(file.path, () {
      final lines = file.readAsLinesSync();
      final problems = <String>[];
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final code = line.trimLeft();
        if (code.startsWith('//')) continue;
        final at = '${file.path}:${i + 1}';
        if (RegExp(r'\bon Object\b').hasMatch(code)) problems.add('$at: on Object');
        if (RegExp(r'\bfinally\b').hasMatch(code)) problems.add('$at: finally');
        if (RegExp(r'(?<!on \w+ )(?<!\.)\bcatch \(').hasMatch(code) &&
            !RegExp(r'\bon [\w<>?$]+ catch \(').hasMatch(code)) {
          problems.add('$at: catch without a typed on');
        }
        if (RegExp(r'\bon Exception catch\b').hasMatch(code)) {
          final next = lines.skip(i + 1).take(3).join('\n');
          if (!next.contains('ErrorUtil.logError(')) {
            problems.add('$at: on Exception catch without ErrorUtil.logError( within 3 lines');
          }
        }
      }
      expect(problems, isEmpty);
    });
  }
}
