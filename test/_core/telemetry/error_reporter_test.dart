import 'dart:async';

import 'package:drift/drift.dart' show LazyDatabase, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/_core/telemetry/error_outbox.dart';
import 'package:flutter_code_agent/_core/telemetry/error_reporter.dart';
import 'package:flutter_code_agent/_core/telemetry/hidden_details_error.dart';
import 'package:flutter_code_agent/_core/telemetry/log_buffer.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';

TelemetryDatabase _db() => TelemetryDatabase.forTesting(NativeDatabase.memory());

final class _Case {
  _Case(this.db, {bool Function(Object)? isExpected, Object Function(Object)? hideDetails}) {
    outbox = ErrorOutbox(
      db,
      appVersion: '1.0.0',
      platform: 'test',
      projectPackages: const {'my_app'},
    );
    reporter = ErrorReporter(
      outbox: outbox,
      buffer: buffer,
      isExpected: isExpected ?? (e) => e is TimeoutException,
      hideDetails: hideDetails,
      console: console.add,
    );
  }

  final TelemetryDatabase db;
  final LogBuffer buffer = LogBuffer();
  final List<String> console = [];
  late final ErrorOutbox outbox;
  late final ErrorReporter reporter;
}

Future<T> _quiet<T extends Object>(Future<T> Function() body) =>
    // ignore: experimental_member_use
    l.capture(body, const LogOptions(output: LogOutput.ignore, handlePrint: false));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('an unexpected error goes to the queue cleaned, an expected one only to the log', () async {
    await _quiet(() async {
      final db = _db();
      addTearDown(db.close);
      final c = _Case(db);
      final sub = l.listen(c.buffer.add);
      addTearDown(sub.cancel);

      await c.reporter.logError(
        StateError('failure pin=1234 Bearer abc.def'),
        StackTrace.current,
        hint: 'ROOT ERROR',
      );
      await c.reporter.logError(TimeoutException('waited too long'), StackTrace.current);

      final entries = await c.outbox.oldest(10);
      expect(entries, hasLength(1));
      expect(entries.single.type, 'StateError');
      expect(entries.single.hint, 'ROOT ERROR');
      expect(entries.single.message, isNot(contains('1234')));
      expect(entries.single.message, isNot(contains('abc.def')));
      expect(c.buffer.lastLines(10).join('\n'), contains('waited too long'));
      return 0;
    });
  });

  test('fatal gives the fatal level, up to 100 log lines without secrets are attached', () async {
    await _quiet(() async {
      final db = _db();
      addTearDown(db.close);
      final c = _Case(db);
      final sub = l.listen(c.buffer.add);
      addTearDown(sub.cancel);
      for (var i = 0; i < 150; i++) {
        l.i('line $i token=secret$i');
      }
      await Future<void>.delayed(Duration.zero);

      await c.reporter.logError(StateError('crash'), StackTrace.current, fatal: true);

      final entry = (await c.outbox.oldest(1)).single;
      expect(entry.level, 'fatal');
      expect(entry.breadcrumbs, hasLength(100));
      expect(entry.breadcrumbs.last, contains('line 149'));
      expect(entry.breadcrumbs.join(), isNot(contains('secret149')));
      return 0;
    });
  });

  test('logMessage puts the message in the queue with the level error or warning', () async {
    await _quiet(() async {
      final db = _db();
      addTearDown(db.close);
      final c = _Case(db);

      await c.reporter.logMessage('backup not made', hint: 'backup');
      await c.reporter.logMessage('low disk space', warning: true);

      expect((await c.outbox.oldest(10)).map((e) => (e.message, e.level, e.type)), [
        ('backup not made', 'error', 'LoggedMessage'),
        ('low disk space', 'warning', 'LoggedMessage'),
      ]);
      return 0;
    });
  });

  test('a failure inside is not thrown and does not call logError again', () async {
    await _quiet(() async {
      final db = _db();
      addTearDown(db.close);
      late _Case c;
      var calls = 0;
      c = _Case(
        db,
        isExpected: (error) {
          calls++;
          unawaited(c.reporter.logError(StateError('nested'), StackTrace.current));
          throw StateError('check failed');
        },
      );

      await c.reporter.logError(StateError('first'), StackTrace.current);

      expect(calls, 1);
      expect(await c.outbox.length(), 0);
      expect(c.console, hasLength(2));
      expect(c.console.first, contains('repeated call'));
      expect(c.console.last, contains('check failed'));
      return 0;
    });
  });

  test('an unavailable queue database is not thrown', () async {
    await _quiet(() async {
      final broken = TelemetryDatabase.forTesting(
        LazyDatabase(() => throw StateError('disk full')),
      );
      final c = _Case(broken);

      await c.reporter.logError(StateError('error'), StackTrace.current);
      await c.reporter.logMessage('message');

      expect(c.console, hasLength(2));
      expect(c.console, everyElement(contains('disk full')));
      return 0;
    });
  });

  test('settled waits for the started records', () async {
    await _quiet(() async {
      final db = _db();
      final c = _Case(db);
      unawaited(c.reporter.logError(StateError('x'), StackTrace.current));
      await c.reporter.settled();
      expect(await c.outbox.length(), 1);
      await db.close();
      return 0;
    });
  });

  group('every error goes out with its full text, cleaned of secrets', () {
    const text = 'secret prompt text';
    const key = 'sk-ant-api03-AbCdEf0123456789AbCdEf0123456789';

    Future<void> expectFullText(Object error, String type) => _quiet(() async {
      final db = _db();
      addTearDown(db.close);
      final c = _Case(db);
      final logged = <String>[];
      final sub = l.listen((m) {
        c.buffer.add(m);
        logged.add('${m.message}');
      });
      addTearDown(sub.cancel);

      await c.reporter.logError(error, StackTrace.current, hint: 'save');
      await c.reporter.logError(StateError('later, unrelated'), StackTrace.current);
      await pumpEventQueue();

      expect(logged.join('\n'), contains(text));
      expect(c.buffer.lastLines(100).join('\n'), contains(text));
      final entries = await c.outbox.oldest(10);
      expect(entries.map((e) => e.type), containsAll([type, 'StateError']));
      final first = entries.firstWhere((e) => e.type == type);
      expect(first.message, contains(text));
      final later = entries.firstWhere((e) => e.type == 'StateError');
      expect(later.breadcrumbs.join('\n'), contains(text));
      for (final out in [
        logged.join('\n'),
        c.buffer.lastLines(100).join('\n'),
        for (final e in entries) ...[e.message, e.stack, e.hint ?? '', ...e.breadcrumbs],
      ]) {
        expect(out, isNot(contains(key)));
      }
      expect(logged.join('\n'), contains('[REDACTED]'));
      return 0;
    });

    test('SqliteException', () async {
      await expectFullText(
        SqliteException(
          extendedResultCode: 2067,
          message: "INSERT INTO chats VALUES ('$text', '$key')",
          causingStatement: "INSERT INTO chats VALUES ('$text', '$key')",
        ),
        'SqliteException',
      );
    });

    test('FormatException', () async {
      await expectFullText(
        const FormatException('Unexpected character $text $key', '{"prompt": "$text"}'),
        'FormatException',
      );
    });

    test('an explicitly passed mapper still hides the text', () async {
      await _quiet(() async {
        final db = _db();
        addTearDown(db.close);
        final c = _Case(db, hideDetails: hideDataDetails);

        await c.reporter.logError(
          SqliteException(extendedResultCode: 2067, message: "INSERT ('$text')"),
          StackTrace.current,
        );

        final entry = (await c.outbox.oldest(10)).single;
        expect(entry.type, 'SqliteException');
        expect(entry.message, isNot(contains(text)));
        expect(entry.message, contains('details hidden'));
        return 0;
      });
    });
  });
}
