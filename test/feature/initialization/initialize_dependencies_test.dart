import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/src/feature/initialization/data/initialization.dart';
import 'package:flutter_code_agent/src/feature/initialization/data/initialize_dependencies.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/initialization_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failed step closes the finished ones in reverse and names the step', () async {
    final closed = <String>[];
    final future = $initializeDependencies(
      steps: {'a': (_) {}, 'b': (_) {}, 'c': (_) => throw const FileSystemException('locked')},
      closers: {
        'a': (_) => closed.add('a'),
        'b': (_) => closed.add('b'),
        'c': (_) => closed.add('c'),
      },
    );
    await expectLater(
      future,
      throwsA(
        isA<InitializationException>()
            .having((e) => e.step, 'step', 'c')
            .having((e) => e.cause, 'cause', isA<FileSystemException>()),
      ),
    );
    expect(closed, <String>['b', 'a']);
  });

  test('a failing closer does not stop the others', () async {
    final closed = <String>[];
    final future = $initializeDependencies(
      steps: {'a': (_) {}, 'b': (_) {}, 'c': (_) => throw StateError('x')},
      closers: {'a': (_) => closed.add('a'), 'b': (_) => throw StateError('close failed')},
    );
    await expectLater(
      future,
      throwsA(isA<InitializationException>().having((e) => e.cause, 'cause', isA<StateError>())),
    );
    expect(closed, <String>['a']);
  });

  test('every closer belongs to a step', () {
    expect(initializationStepsForTest.keys, containsAll(initializationClosersForTest.keys));
  });

  test('installs the error handlers once over two failed attempts', () async {
    final before = handlerInstalls;
    for (var i = 0; i < 2; i++) {
      await expectLater(
        $initializeApp(steps: {'a': (_) => throw StateError('x')}),
        throwsA(isA<InitializationException>()),
      );
    }
    expect(handlerInstalls - before, lessThanOrEqualTo(1));
    expect(handlerInstalls, 1);
    // keep the widgets binding quiet
    expect(WidgetsBinding.instance, isNotNull);
  });
}
