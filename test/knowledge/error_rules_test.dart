import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _rule(String name) => File('assets/knowledge/rules/$name.md').readAsStringSync();

Iterable<String> _dartBlocks(String markdown) => RegExp(
  r'```dart\n(.*?)```',
  dotAll: true,
).allMatches(markdown).map((match) => match.group(1)!);

void main() {
  test('controllers.md has the handle recipe', () {
    final controllers = _rule('controllers');
    expect(controllers, contains('error: (error, stackTrace) async =>'));
    expect(controllers, contains('done: () async =>'));
    expect(controllers, contains('### Where the error goes'));
    expect(controllers, contains('#### Typed `on` with `rethrow`'));
    expect(controllers, contains('### An action of two steps'));
    expect(controllers, contains('### Reporting an error'));
  });

  test('no controller example catches everything', () {
    for (final name in ['controllers', 'architecture']) {
      for (final block in _dartBlocks(_rule(name)).where((block) => block.contains('handle('))) {
        expect(block, isNot(contains('on Object catch')), reason: '$name.md: $block');
        expect(block, isNot(contains('} finally {')), reason: '$name.md: $block');
      }
    }
  });

  test('no cafe specifics', () {
    for (final name in ['controllers', 'repositories', 'architecture']) {
      final text = _rule(name);
      for (final word in ['CAFEPOS', 'deviceGuard', 'venue', 'заведени', 'PIN']) {
        expect(text, isNot(contains(word)), reason: '$name.md contains $word');
      }
    }
  });

  test('repositories.md reports with ErrorUtil', () {
    expect(_rule('repositories'), contains('**Report with `ErrorUtil`, nothing else.**'));
  });
}
