import 'dart:async';

import 'package:flutter_code_agent/src/common/utils/error_util.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/error_log_support.dart';

void main() {
  late List<String> console;

  setUp(() {
    console = <String>[];
    ErrorUtil.reset();
    ErrorUtil.console = console.add;
  });

  tearDown(() async {
    await ErrorUtil.settled();
    ErrorUtil.reset();
  });

  quietTest('before configure an error goes to the console, after it into the queue', () async {
    final runtime = memoryRuntime();

    await ErrorUtil.logError(StateError('too early'), StackTrace.current);
    expect(console.single, contains('too early'));
    expect(await runtime.outbox.length(), 0);

    ErrorUtil.configure(runtime);
    await ErrorUtil.logError(StateError('configured'), StackTrace.current, hint: 'Hint');
    await ErrorUtil.settled();

    final queue = await runtime.outbox.oldest(10);
    expect(queue.map((entry) => entry.hint), contains('Hint'));
    expect(queue.map((entry) => entry.message), contains(contains('configured')));
  });

  quietTest('an expected failure is not queued', () async {
    final runtime = memoryRuntime();
    ErrorUtil.configure(runtime);

    await ErrorUtil.logError(TimeoutException('slow'), StackTrace.current);
    await ErrorUtil.settled();

    expect(await runtime.outbox.length(), 0);
  });

  quietTest('logError never throws when the outbox fails', () async {
    final runtime = memoryRuntime();
    ErrorUtil.configure(runtime);
    await runtime.outbox.length();
    await runtime.db.close();

    await ErrorUtil.logError(StateError('after the database closed'), StackTrace.current);

    expect(console, isNotEmpty);
  });

  quietTest('disconnect: later errors pile up in memory, not in the closed log', () async {
    final runtime = memoryRuntime();
    ErrorUtil.configure(runtime);
    await ErrorUtil.settled();
    ErrorUtil.disconnect(runtime);

    await ErrorUtil.logError(StateError('after disconnect'), StackTrace.current);

    expect(await runtime.outbox.length(), 0);
  });
}
