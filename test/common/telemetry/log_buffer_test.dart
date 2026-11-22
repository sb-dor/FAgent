import 'dart:async';
import 'dart:isolate';

import 'package:flutter_code_agent/src/common/telemetry/log_buffer.dart';
import 'package:flutter_code_agent/src/common/telemetry/log_record.dart';
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
    expect(watch.elapsedMilliseconds, lessThan(1000));
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

  test('10 000 lines of 16 KB: the main isolate is not blocked for more than 50 ms', () async {
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
    var longest = Duration.zero;
    var last = Stopwatch()..start();
    final ticker = Timer.periodic(const Duration(milliseconds: 5), (_) {
      if (last.elapsed > longest) longest = last.elapsed;
      last = Stopwatch()..start();
    });

    final raw = buffer.rawLines(LogBuffer.limit);
    final joined = await Isolate.run(() => formatRawLogLines(raw));
    ticker.cancel();

    expect(joined.split('\n'), hasLength(LogBuffer.limit));
    expect(longest, lessThan(const Duration(milliseconds: 50)));
  });
}
