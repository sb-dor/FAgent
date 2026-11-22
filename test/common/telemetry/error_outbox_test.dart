import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/telemetry/error_outbox.dart';
import 'package:flutter_code_agent/src/common/telemetry/fingerprint.dart';
import 'package:flutter_code_agent/src/common/telemetry/telemetry_database.dart';
import 'package:flutter_test/flutter_test.dart';

final _stack = StackTrace.fromString('#0 Repo.load (package:my_app/repo.dart:10:5)');

TelemetryDatabase _db() => TelemetryDatabase.forTesting(NativeDatabase.memory());

ErrorOutbox _outbox(TelemetryDatabase db, {int capacity = 200}) => ErrorOutbox(
  db,
  appVersion: '1.2.0',
  platform: 'macos',
  projectPackages: const {'my_app'},
  capacity: capacity,
);

// A name of letters: digits in a message are merged, so different errors differ by letters.
String _name(int i) {
  var n = i;
  final buffer = StringBuffer();
  do {
    buffer.writeCharCode(97 + n % 26);
    n ~/= 26;
  } while (n > 0);
  return buffer.toString();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('the same error 500 times gives one entry with count 500', () async {
    final db = _db();
    addTearDown(db.close);
    final outbox = _outbox(db);
    for (var i = 0; i < 500; i++) {
      await outbox.add(
        error: StateError('Order $i not found'),
        stack: _stack,
        level: 'error',
        breadcrumbs: const ['a'],
      );
    }
    expect(await outbox.length(), 1);
    final entry = (await outbox.oldest(10)).single;
    expect(entry.count, 500);
    expect(entry.type, 'StateError');
    expect(entry.appVersion, '1.2.0');
    expect(entry.platform, 'macos');
    expect(entry.level, 'error');
  });

  test('merging updates lastAt, firstAt stays the first', () async {
    final db = _db();
    addTearDown(db.close);
    final outbox = _outbox(db);
    final t0 = DateTime.utc(2026, 11, 12, 10);
    for (final t in [t0, t0.add(const Duration(hours: 1))]) {
      await withClock(Clock.fixed(t), () {
        return outbox.add(error: StateError('x'), stack: _stack, level: 'error', breadcrumbs: []);
      });
    }
    final entry = (await outbox.oldest(1)).single;
    expect(entry.firstAt, t0);
    expect(entry.lastAt, t0.add(const Duration(hours: 1)));
    expect(entry.count, 2);
  });

  test('more than 200 different: 200 stay, the oldest by lastAt is evicted', () async {
    final db = _db();
    addTearDown(db.close);
    final outbox = _outbox(db);
    var now = DateTime.utc(2026, 11, 12);
    Future<void> add(int i) async {
      now = now.add(const Duration(seconds: 1));
      await withClock(Clock.fixed(now), () {
        return outbox.add(
          error: StateError('error ${_name(i)}'),
          stack: _stack,
          level: 'error',
          breadcrumbs: [],
        );
      });
    }

    for (var i = 0; i < 200; i++) {
      await add(i);
    }
    await add(0);
    await add(200);
    expect(await outbox.length(), 200);
    final messages = (await outbox.oldest(300)).map((e) => e.message).toList();
    expect(messages, contains('Bad state: error ${_name(0)}'));
    expect(messages, contains('Bad state: error ${_name(200)}'));
    expect(messages, isNot(contains('Bad state: error ${_name(1)}')));

    for (var i = 201; i < 300; i++) {
      await add(i);
    }
    expect(await outbox.length(), 200);
    final last = await outbox.oldest(300);
    expect(last.map((e) => e.message), contains('Bad state: error ${_name(299)}'));
  });

  test('the queue gets cleaned text and breadcrumbs', () async {
    final db = _db();
    addTearDown(db.close);
    final outbox = _outbox(db);
    await outbox.add(
      error: StateError('Request with Bearer abc123secret failed'),
      stack: StackTrace.fromString('#0 f (package:my_app/a.dart:1:1) password=hunter2'),
      hint: 'pin: 4821 for anna@example.com',
      level: 'error',
      breadcrumbs: [
        'key sk-AbCdEf0123456789AbCdEf0123 used',
        'call +992 900 12 34 56',
        'plain line',
      ],
    );
    final e = (await outbox.oldest(1)).single;
    final all = [e.message, e.stack, e.hint, ...e.breadcrumbs].join('\n');
    for (final secret in [
      'abc123secret',
      'hunter2',
      '4821',
      'anna@example.com',
      'AbCdEf0123456789',
      '900 12 34',
    ]) {
      expect(all, isNot(contains(secret)), reason: secret);
    }
    expect(e.message, contains('[REDACTED]'));
    expect(e.breadcrumbs.last, 'plain line');
    final raw = await db.select(db.errorOutboxEntries).getSingle();
    expect(jsonDecode(raw.breadcrumbs), isA<List<dynamic>>());
  });

  test('markAttempt increases attempts, remove deletes an entry', () async {
    final db = _db();
    addTearDown(db.close);
    final outbox = _outbox(db);
    await outbox.add(error: StateError('x'), stack: _stack, level: 'error', breadcrumbs: []);
    final id = (await outbox.oldest(1)).single.id;
    await outbox.markAttempt(id);
    await outbox.markAttempt(id);
    expect((await outbox.oldest(1)).single.attempts, 2);
    await outbox.remove(id);
    expect(await outbox.length(), 0);
  });

  test('ReportedError substitutes the original type into the entry and the fingerprint', () async {
    final db = _db();
    addTearDown(db.close);
    final outbox = _outbox(db);

    await outbox.add(
      error: _Hidden('SqliteException'),
      stack: _stack,
      level: 'error',
      breadcrumbs: const [],
    );

    expect((await outbox.oldest(1)).single.type, 'SqliteException');
    expect(errorTypeName(_Hidden('X')), 'X');
    expect(errorTypeName(StateError('a')), 'StateError');
    expect(
      errorFingerprint(_Hidden('A'), _stack, projectPackages: const {'my_app'}),
      isNot(errorFingerprint(_Hidden('B'), _stack, projectPackages: const {'my_app'})),
    );
  });

  test('clear empties the queue and onChanged is called', () async {
    final db = _db();
    addTearDown(db.close);
    final outbox = _outbox(db);
    var changed = 0;
    outbox.onChanged = () => changed++;
    await outbox.add(error: StateError('x'), stack: _stack, level: 'error', breadcrumbs: []);

    await outbox.clear();

    expect(await outbox.length(), 0);
    expect(changed, 2);
  });

  test('recent: the latest by lastAt, at most n', () async {
    final db = _db();
    addTearDown(db.close);
    final outbox = _outbox(db);
    final now = DateTime.utc(2026, 11, 1);
    for (var i = 0; i < 5; i++) {
      await withClock(
        Clock.fixed(now.add(Duration(minutes: i))),
        () => outbox.add(
          error: StateError(_name(i)),
          stack: _stack,
          level: 'error',
          breadcrumbs: const [],
        ),
      );
    }

    final recent = await outbox.recent(3);

    expect(recent.map((e) => e.message), [
      'Bad state: ${_name(4)}',
      'Bad state: ${_name(3)}',
      'Bad state: ${_name(2)}',
    ]);
  });
}

final class _Hidden implements ReportedError {
  _Hidden(this.reportedType);

  @override
  final String reportedType;
}
