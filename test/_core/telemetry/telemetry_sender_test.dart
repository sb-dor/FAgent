import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_code_agent/_core/telemetry/crash_report_gateway.dart';
import 'package:flutter_code_agent/_core/telemetry/error_outbox.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry_database.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry_sender.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';

final _stack = StackTrace.fromString('#0 Repo.load (package:my_app/repo.dart:10:5)');

class _Gateway implements ICrashReportGateway {
  bool isReachable = true;
  int reachableCalls = 0;
  int concurrent = 0;
  int maxConcurrent = 0;
  Duration delay = Duration.zero;
  final sent = <String>[];

  /// What to return for an entry: true, false or an exception.
  FutureOr<bool> Function(OutboxEntry e) onSend = (_) => true;

  @override
  Future<bool> reachable() async {
    reachableCalls++;
    return isReachable;
  }

  @override
  Future<bool> send(OutboxEntry e) async {
    concurrent++;
    if (concurrent > maxConcurrent) {
      maxConcurrent = concurrent;
    }
    try {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      final ok = await onSend(e);
      if (ok) {
        sent.add(e.message);
      }
      return ok;
    } finally {
      concurrent--;
    }
  }
}

String _name(int i) {
  var n = i;
  final buffer = StringBuffer();
  do {
    buffer.writeCharCode(97 + n % 26);
    n ~/= 26;
  } while (n > 0);
  return buffer.toString();
}

Future<void> _fill(ErrorOutbox outbox, int n, {String prefix = 'error', int from = 0}) async {
  for (var i = from; i < from + n; i++) {
    await outbox.add(
      error: StateError('$prefix ${_name(i)}'),
      stack: _stack,
      level: 'error',
      breadcrumbs: [],
    );
  }
}

/// A test whose log output is swallowed: the test output stays pristine.
void _test(String name, Future<void> Function() body) => test(
  name,
  // ignore: experimental_member_use
  () => l.capture(body, const LogOptions(output: LogOutput.ignore, handlePrint: false)),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late TelemetryDatabase db;
  late ErrorOutbox outbox;
  late _Gateway gateway;
  var enabled = true;

  setUp(() {
    db = TelemetryDatabase.forTesting(NativeDatabase.memory());
    outbox = ErrorOutbox(
      db,
      appVersion: '1.0.0',
      platform: 'android',
      projectPackages: const {'my_app'},
    );
    gateway = _Gateway();
    enabled = true;
  });
  tearDown(() => db.close());

  TelemetrySender sender({int perPass = 50, int maxAttempts = 3}) => TelemetrySender(
    outbox: outbox,
    gateway: gateway,
    enabled: () => enabled,
    perPass: perPass,
    maxAttempts: maxAttempts,
  );

  _test('pass: Sentry unreachable, nothing is sent, the queue is intact', () async {
    await _fill(outbox, 3);
    gateway.isReachable = false;
    final s = sender();
    await s.runPass();
    expect(gateway.sent, isEmpty);
    expect(await outbox.length(), 3);
    expect(s.current.reachable, isFalse);
    expect(s.current.lastCheckAt, isNotNull);
    expect(s.current.lastSentAt, isNull);
    expect(s.current.queued, 3);
    expect(s.current.sending, isFalse);
  });

  _test('pass: one by one, at most 50, removes the accepted, keeps the rejected', () async {
    await _fill(outbox, 60);
    final s = sender();
    await s.runPass();
    expect(gateway.sent, hasLength(50));
    expect(gateway.maxConcurrent, 1);
    expect(await outbox.length(), 10);
    expect(s.current.lastSentAt, isNotNull);
    expect(s.current.queued, 10);

    gateway.onSend = (e) => !e.message.endsWith(' ${_name(55)}');
    await s.runPass();
    expect(await outbox.length(), 1);
    final left = (await outbox.oldest(5)).single;
    expect(left.message, endsWith(' ${_name(55)}'));
    expect(left.attempts, 1);
  });

  _test('connection failure on the 3rd entry: the first two are removed, the rest wait for the next pass', () async {
    await _fill(outbox, 5);
    var calls = 0;
    gateway.onSend = (e) {
      calls++;
      if (calls >= 3) {
        throw const FormatException('connection lost');
      }
      return true;
    };
    final s = sender();
    await s.runPass();
    expect(gateway.sent, hasLength(2));
    expect(await outbox.length(), 3);
    expect((await outbox.oldest(5)).every((e) => e.attempts == 0), isTrue);

    gateway
      ..isReachable = true
      ..onSend = (_) => true;
    await s.runPass();
    expect(await outbox.length(), 0);
  });

  _test('P1(a): 60 entries, Sentry accepts 10 per pass, good ones are not deleted', () async {
    await _fill(outbox, 60);
    var acceptedInPass = 0;
    gateway.onSend = (_) => acceptedInPass++ < 10;
    final s = sender();
    var removed = 0;
    for (var i = 0; i < 6; i++) {
      acceptedInPass = 0;
      await s.runPass();
      removed += 10;
      expect(await outbox.length(), 60 - removed);
      expect((await outbox.oldest(100)).every((e) => e.attempts == 0), isTrue);
    }
    expect(gateway.sent, hasLength(60));
  });

  _test('P1(b): two bad ones, the good ones after them go in the pass, the bad ones are removed after 3 passes', () async {
    gateway.onSend = (e) => !e.message.contains('BAD');
    for (final name in ['BADx', 'BADy']) {
      await outbox.add(error: StateError(name), stack: _stack, level: 'error', breadcrumbs: []);
    }
    final s = sender();
    for (var pass = 0; pass < 3; pass++) {
      await _fill(outbox, 3, prefix: 'good', from: pass * 10);
      await s.runPass();
      final left = await outbox.oldest(10);
      expect(left.map((e) => e.attempts), pass < 2 ? [pass + 1, pass + 1] : isEmpty);
    }
    expect(gateway.sent, hasLength(9));
    expect(await outbox.length(), 0);
  });

  _test('P1(c): all rejected, the queue is intact, no attempts', () async {
    await _fill(outbox, 5);
    gateway.onSend = (_) => false;
    final s = sender();
    for (var i = 0; i < 6; i++) {
      await s.runPass();
    }
    expect(await outbox.length(), 5);
    expect((await outbox.oldest(10)).every((e) => e.attempts == 0), isTrue);
  });

  _test('P1(d): a lone bad entry is not removed', () async {
    await _fill(outbox, 1);
    gateway.onSend = (_) => false;
    final s = sender();
    for (var i = 0; i < 6; i++) {
      await s.runPass();
    }
    final left = (await outbox.oldest(10)).single;
    expect(left.attempts, 0);
  });

  _test('P1: the rejected tail of a pass after the last accepted gets no attempts', () async {
    await _fill(outbox, 4);
    var calls = 0;
    gateway.onSend = (_) => ++calls <= 2;
    final s = sender();
    await s.runPass();
    expect(gateway.sent, hasLength(2));
    expect((await outbox.oldest(10)).map((e) => e.attempts), [0, 0]);
  });

  _test(
    'a whole pass rejected while Sentry is reachable: the next one starts with the newest',
    () async {
      // Three old bad entries must not block the new ones forever.
      await _fill(outbox, 6);
      final bad = {_name(0), _name(1), _name(2)};
      gateway.onSend = (e) => !bad.any((n) => e.message.endsWith(' $n'));
      final s = sender(perPass: 3);

      await s.runPass();
      expect(gateway.sent, isEmpty);
      expect(await outbox.length(), 6);

      await s.runPass();
      expect(gateway.sent.map((m) => m.substring(m.length - 1)), [_name(3), _name(4), _name(5)]);
      expect(await outbox.length(), 3);
    },
  );

  _test(
    'P5: dispose drops the queue subscription, runPass after stop without start works',
    () async {
      await _fill(outbox, 2);
      final s = sender();
      unawaited(s.stop());
      await s.runPass();
      expect(gateway.sent, hasLength(2));
      await s.dispose();
      expect(outbox.onChanged, isNull);
    },
  );

  _test('a rejection with a lost connection is not counted as the entry being refused', () async {
    await _fill(outbox, 3);
    gateway.onSend = (e) {
      gateway.isReachable = false;
      return false;
    };
    final s = sender();
    await s.runPass();
    expect(await outbox.length(), 3);
    expect((await outbox.oldest(5)).every((e) => e.attempts == 0), isTrue);
  });

  _test('an entry rejected 3 times while Sentry is reachable is removed', () async {
    await _fill(outbox, 2);
    gateway.onSend = (e) => !e.message.endsWith(' ${_name(0)}');
    final s = sender();
    await s.runPass();
    // A lone bad entry looks like a sick Sentry: attempts count only when good entries are near.
    await _fill(outbox, 1, prefix: 'new', from: 100);
    await s.runPass();
    final stuck = await outbox.oldest(5);
    expect(stuck.single.attempts, 2);
    await _fill(outbox, 1, prefix: 'more', from: 200);
    await s.runPass();
    expect(await outbox.length(), 0);
  });

  _test('enabled() == false: the pass does nothing; once enabled the next pass sends', () async {
    await _fill(outbox, 2);
    enabled = false;
    final s = sender();
    await s.runPass();
    expect(gateway.reachableCalls, 0);
    expect(gateway.sent, isEmpty);
    expect(await outbox.length(), 2);

    enabled = true;
    await s.runPass();
    expect(gateway.sent, hasLength(2));
    expect(await outbox.length(), 0);
  });

  _test('a second pass during the first does not start', () async {
    await _fill(outbox, 2);
    gateway.delay = const Duration(milliseconds: 20);
    final s = sender();
    await Future.wait([s.runPass(), s.runPass()]);
    expect(gateway.reachableCalls, 1);
    expect(gateway.sent, hasLength(2));
  });

  _test('a queue failure is not thrown out', () async {
    final s = sender();
    await db.close();
    await expectLater(s.runPass(), completes);
    expect(s.current.sending, isFalse);
  });

  _test('timer: a pass at start and every 5 minutes; status.sending during a pass', () async {
    await _fill(outbox, 1);
    fakeAsync((async) {
      gateway.delay = const Duration(seconds: 1);
      final s = sender();
      final seen = <bool>[];
      final sub = s.status.listen((st) => seen.add(st.sending));
      s.start();
      async.flushMicrotasks();
      expect(gateway.reachableCalls, 1);
      expect(s.current.sending, isTrue);
      async.elapse(const Duration(seconds: 2));
      expect(s.current.sending, isFalse);
      expect(seen, containsAllInOrder([true, false]));

      async.elapse(const Duration(minutes: 5));
      expect(gateway.reachableCalls, 2);
      async.elapse(const Duration(minutes: 5));
      expect(gateway.reachableCalls, 3);

      s.stop();
      async.elapse(const Duration(minutes: 20));
      expect(gateway.reachableCalls, 3);
      sub.cancel();
    });
  });

  _test('Sentry reachable but refuses everything (5xx, 429): 5 passes, the queue is intact, no attempts', () async {
    await _fill(outbox, 4);
    gateway.onSend = (_) => false;
    final s = sender();
    for (var i = 0; i < 5; i++) {
      await s.runPass();
    }
    expect(await outbox.length(), 4);
    expect((await outbox.oldest(10)).every((e) => e.attempts == 0), isTrue);
  });

  _test(
    'one bad among good ones: the good ones go, the bad one is removed after 3 passes',
    () async {
      await _fill(outbox, 4);
      gateway.onSend = (e) => !e.message.endsWith(' ${_name(0)}');
      final s = sender();
      await s.runPass();
      expect(gateway.sent, hasLength(3));
      expect((await outbox.oldest(10)).single.attempts, 1);
      await _fill(outbox, 1, prefix: 'new', from: 100);
      await s.runPass();
      await _fill(outbox, 1, prefix: 'more', from: 200);
      await s.runPass();
      expect(await outbox.length(), 0);
    },
  );

  _test(
    'a permanent exception for one entry with a live connection: the neighbours go, it is removed',
    () async {
      await _fill(outbox, 3);
      gateway.onSend = (e) {
        if (e.message.endsWith(' ${_name(1)}')) {
          throw const FormatException('broken entry');
        }
        return true;
      };
      final s = sender();
      await s.runPass();
      expect(gateway.sent, hasLength(2));
      await _fill(outbox, 1, prefix: 'new', from: 100);
      await s.runPass();
      await _fill(outbox, 1, prefix: 'more', from: 200);
      await s.runPass();
      expect(await outbox.length(), 0);
    },
  );

  _test('queued grows after add outside a pass', () async {
    final s = sender();
    expect(s.current.queued, 0);
    await _fill(outbox, 2);
    await Future<void>.delayed(Duration.zero);
    expect(s.current.queued, 2);
    await _fill(outbox, 3, prefix: 'other');
    await Future<void>.delayed(Duration.zero);
    expect(s.current.queued, 5);
  });

  _test('stop during a pass interrupts it; dispose closes the status stream', () async {
    await _fill(outbox, 10);
    gateway.delay = const Duration(milliseconds: 10);
    final s = sender();
    final pass = s.runPass();
    await Future<void>.delayed(const Duration(milliseconds: 25));
    final stopped = s.stop();
    await stopped;
    expect(s.current.sending, isFalse, reason: 'stop waited for the end of the pass');
    await pass;
    expect(gateway.sent.length, lessThan(10));
    expect(await outbox.length(), greaterThan(0));
    var done = false;
    s.status.listen((_) {}, onDone: () => done = true);
    await s.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(done, isTrue);
  });

  test('TelemetryStatus: toJson and fromJson, a wrong format is a FormatException', () {
    final status = TelemetryStatus(
      queued: 4,
      sending: false,
      lastSentAt: DateTime.utc(2026, 11, 12, 10),
      lastCheckAt: null,
      reachable: true,
    );
    final back = TelemetryStatus.fromJson(status.toJson());
    expect(back.queued, 4);
    expect(back.lastSentAt, DateTime.utc(2026, 11, 12, 10));
    expect(back.lastCheckAt, isNull);
    expect(back.reachable, isTrue);
    expect(() => TelemetryStatus.fromJson('x'), throwsFormatException);
    expect(() => TelemetryStatus.fromJson(<String, Object?>{'queued': 'a'}), throwsFormatException);
  });
}
