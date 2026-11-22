import 'package:control/control.dart';
import 'package:flutter_code_agent/src/common/controller/controller_observer.dart';
import 'package:flutter_code_agent/src/common/utils/error_util.dart';
import 'package:flutter_code_agent/src/common/utils/expected_exception.dart';
import 'package:flutter_code_agent/src/feature/sessions/data/sessions_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';

import '../../support/error_log_support.dart';

enum _Phase { idle, processing, error }

final class _Counter extends StateController<_Phase> with DroppableControllerHandler {
  _Counter() : super(initialState: _Phase.idle);

  Future<void> fail(Object error) => handle(
    () async {
      setState(_Phase.processing);
      Error.throwWithStackTrace(error, StackTrace.current);
    },
    error: (error, stackTrace) async => setState(_Phase.error),
    done: () async => setState(_Phase.idle),
  );
}

void main() {
  late _Counter controller;

  setUp(() {
    controller = _Counter();
    ErrorUtil.reset();
    ErrorUtil.console = (_) {};
  });

  tearDown(() async {
    controller.dispose();
    await ErrorUtil.settled();
    ErrorUtil.reset();
  });

  quietTest('a ChatBusyException is an ExpectedException', () async {
    expect(const ChatBusyException(1), isA<ExpectedException>());
  });

  quietTest('an expected failure: processing, error, idle, one log line, an empty queue', () async {
    final runtime = memoryRuntime();
    ErrorUtil.configure(runtime);
    Controller.observer = const ControllerObserver();
    addTearDown(() => Controller.observer = null);
    final phases = <_Phase>[];
    controller.addListener(() => phases.add(controller.state));
    final logged = <LogMessage>[];
    final sub = l.listen(logged.add);
    addTearDown(sub.cancel);

    await controller.fail(const ChatBusyException(1));
    await ErrorUtil.settled();
    await Future<void>.delayed(Duration.zero);

    expect(phases, [_Phase.processing, _Phase.error, _Phase.idle]);
    expect(
      logged.where((message) => message.message.toString().contains('_Counter failed')),
      hasLength(1),
    );
    expect(await runtime.outbox.length(), 0);
  });

  quietTest('a bug: one entry in the queue', () async {
    final runtime = memoryRuntime();
    ErrorUtil.configure(runtime);
    Controller.observer = const ControllerObserver();
    addTearDown(() => Controller.observer = null);

    await controller.fail(StateError('broken'));
    await ErrorUtil.settled();
    await Future<void>.delayed(Duration.zero);

    final queue = await runtime.outbox.oldest(10);
    expect(queue, hasLength(1));
    expect(queue.single.hint, contains('_Counter failed'));
  });

  quietTest('a state change logs the types only', () async {
    final logged = <LogMessage>[];
    final sub = l.listen(logged.add);
    addTearDown(sub.cancel);

    const ControllerObserver().onStateChanged<Object>(controller, 'secret-prev', 'secret-next');
    await Future<void>.delayed(Duration.zero);

    final text = logged.map((message) => message.message.toString()).join('\n');
    expect(text, contains('String -> String'));
    expect(text, isNot(contains('secret')));
  });
}
