import 'dart:async';
import 'dart:io';

import 'package:flutter_code_agent/initialization/data/initialization.dart';
import 'package:flutter_code_agent/initialization/data/initialize_dependencies.dart';
import 'package:flutter_code_agent/initialization/models/initialization_exception.dart';
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

  test('the custom agents are followed through the agents repository, once it exists', () {
    final steps = initializationStepsForTest.keys.toList();
    expect(steps, isNot(contains('Create custom agents repository')));
    expect(
      steps.indexOf('Create agents repository'),
      lessThan(steps.indexOf('Follow custom agents')),
    );
  });

  test('installs the error handlers once over two failed attempts', () async {
    final before = handlerInstalls;
    for (var i = 0; i < 2; i++) {
      await expectLater(
        $initializeApp(steps: {'a': (_) => throw StateError('x')}),
        throwsA(isA<InitializationException>()),
      );
    }
    expect(handlerInstalls - before, 1);
  });

  test(
    'a step past the deadline fails the run, and its closer runs when it finally completes',
    () async {
      final events = <String>[];
      final late = Completer<void>();
      final future = $initializeDependencies(
        timeout: const Duration(milliseconds: 50),
        steps: {'a': (_) {}, 'slow': (_) => late.future, 'after': (_) => events.add('after ran')},
        closers: {
          'a': (_) => events.add('close a'),
          'slow': (_) => events.add('close slow'),
          'after': (_) => events.add('close after'),
        },
      );
      await expectLater(
        future,
        throwsA(
          isA<InitializationException>()
              .having((e) => e.step, 'step', 'slow')
              .having((e) => e.cause, 'cause', isA<TimeoutException>()),
        ),
      );
      expect(events, <String>['close a']);
      late.complete();
      await pumpEventQueue();
      expect(events, <String>['close a', 'close slow']);
    },
  );
}
