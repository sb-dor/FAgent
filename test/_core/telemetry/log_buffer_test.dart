import 'dart:isolate';

import 'package:flutter_code_agent/_core/telemetry/log_buffer.dart';
import 'package:flutter_code_agent/_core/telemetry/log_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';

LogMessage _m(int i) => LogMessage.verbose(
  message: 'm$i',
  level: const LogLevel.info(),
  timestamp: DateTime.utc(2026, 11, 12).add(Duration(seconds: i)),
);

void main() {
  test('LogBuffer keeps the last 10000, addAll over the limit keeps the newest', () {
    final buffer = LogBuffer();
    for (var i = 0; i < LogBuffer.limit + 5; i++) {
      buffer.add(_m(i));
    }
    expect(buffer.logs.length, LogBuffer.limit);
    expect(buffer.logs.first.message, 'm5');
    expect(buffer.logs.last.message, 'm${LogBuffer.limit + 4}');

    final bulk = LogBuffer()..addAll([for (var i = 0; i < LogBuffer.limit + 3; i++) _m(i)]);
    expect(bulk.logs.length, LogBuffer.limit);
    expect(bulk.logs.first.message, 'm3');
  });

  test('lastLines gives the last n lines from oldest to newest, fewer if there are few', () {
    final buffer = LogBuffer()..addAll([for (var i = 0; i < 5; i++) _m(i)]);
    final lines = buffer.lastLines(2);
    expect(lines, hasLength(2));
    expect(lines.first, endsWith('m3'));
    expect(lines.last, endsWith('m4'));
    expect(buffer.lastLines(100), hasLength(5));
    expect(LogBuffer().lastLines(3), isEmpty);
  });

  test('lastLines of a big buffer does not copy it whole and gives the right lines', () {
    final buffer = LogBuffer()..addAll([for (var i = 0; i < LogBuffer.limit; i++) _m(i)]);
    final watch = Stopwatch()..start();
    for (var i = 0; i < 1000; i++) {
      buffer.lastLines(100);
    }
    // A guard against copying the whole buffer per call, not a speed test: wide for a loaded CI.
    expect(watch.elapsedMilliseconds, lessThan(10000));
    final lines = buffer.lastLines(3);
    expect(lines.last, endsWith('m${LogBuffer.limit - 1}'));
    expect(lines.first, endsWith('m${LogBuffer.limit - 3}'));
  });

  test('clear removes all records', () {
    final buffer = LogBuffer()
      ..addAll([for (var i = 0; i < 5; i++) _m(i)])
      ..clear();
    expect(buffer.logs, isEmpty);
  });

  test('rawLines and formatRawLogLines give the same lines as lastLines', () {
    final buffer = LogBuffer()..addAll([for (var i = 0; i < 5; i++) _m(i)]);

    expect(formatRawLogLines(buffer.rawLines(3)), buffer.lastLines(3).join('\n'));
    expect(buffer.rawLines(100), hasLength(5));
  });

  // No wall-clock bound on the main isolate: one that held on a fast machine failed on a slow one
  // (51 ms against 50). What stays is what the archive relies on: the raw lines cross to another
  // isolate and come back formatted, every one of them.
  test('10 000 lines of 16 KB are formatted in another isolate, every line', () async {
    final text = 'a1 ' * 5462; // 16 KB, one line for all
    final buffer = LogBuffer()
      ..addAll([
        for (var i = 0; i < LogBuffer.limit; i++)
          LogMessage.verbose(
            message: text,
            level: const LogLevel.info(),
            timestamp: DateTime.utc(2026, 11, 12).add(Duration(seconds: i)),
          ),
      ]);

    final raw = buffer.rawLines(LogBuffer.limit);
    final joined = await Isolate.run(() => formatRawLogLines(raw));

    final lines = joined.split('\n');
    expect(lines, hasLength(LogBuffer.limit));
    // The same text as formatting on this isolate: nothing is lost on the way.
    expect(joined, formatRawLogLines(raw));
  });
}
