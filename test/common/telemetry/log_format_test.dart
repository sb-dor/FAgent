import 'package:flutter_code_agent/src/common/telemetry/log_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';

void main() {
  test(r'formatLogLine: UTC time, level, a line break as \n', () {
    final line = formatLogLine(
      LogMessage.verbose(
        message: 'a\nb',
        level: const LogLevel.error(),
        timestamp: DateTime.utc(2026, 11, 12, 10, 15, 3, 120),
      ),
    );
    expect(line, r'2026-11-12T10:15:03.120Z [E] a\nb');
  });

  test('formatLogLine cleans secrets and clips a long line to 1000 characters', () {
    final secret = formatLogLine(
      LogMessage.verbose(
        message: 'Authorization: Bearer abc.def',
        level: const LogLevel.info(),
        timestamp: DateTime.utc(2026),
      ),
    );
    expect(secret, isNot(contains('abc.def')));
    expect(secret, contains('Bearer [REDACTED]'));

    final long = formatLogLine(
      LogMessage.verbose(
        message: 'x' * 5000,
        level: const LogLevel.info(),
        timestamp: DateTime.utc(2026),
      ),
    );
    expect(long.length, lessThanOrEqualTo(1000));
    expect(long, endsWith('…'));
  });

  test('the line time is in milliseconds UTC, a live record the same as one read from the db', () {
    final live = formatLogLine(LogMessage.create('x', const LogLevel.info()));
    expect(live, matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z \[I\] x$')));
  });

  test('clipping to 1000 does not split a surrogate pair', () {
    for (var pad = 0; pad < 4; pad++) {
      final line = formatLogLine(
        LogMessage.verbose(
          message: '${'x' * pad}${'😀' * 600}',
          level: const LogLevel.info(),
          timestamp: DateTime.utc(2026),
        ),
      );
      expect(line.length, lessThanOrEqualTo(1000));
      final last = line.codeUnitAt(line.length - 1);
      expect(last >= 0xD800 && last <= 0xDBFF, isFalse, reason: 'pad $pad');
    }
  });

  test('a huge message is cleaned fast', () {
    final watch = Stopwatch()..start();
    formatLogLine(
      LogMessage.verbose(
        message: 'a1.' * 200000,
        level: const LogLevel.info(),
        timestamp: DateTime.utc(2026),
      ),
    );
    // A guard against catastrophic backtracking, not a speed test: wide for a loaded CI.
    expect(watch.elapsedMilliseconds, lessThan(2000));
  });

  group('a stub of a secret on the clipping boundary does not reach the line', () {
    String line(String message) => formatLogLine(
      LogMessage.verbose(
        message: message,
        level: const LogLevel.info(),
        timestamp: DateTime.utc(2026),
      ),
    );

    test('40 e-mails in a row at any shift', () {
      final mails = [for (var i = 0; i < 40; i++) '"staff.member$i@example.com"'].join(',');
      for (var pad = 0; pad < 60; pad++) {
        final result = line('server reply: ${'x' * pad}[$mails]');
        expect(result, isNot(matches(RegExp(r'staff\.member\d+'))), reason: 'pad $pad');
        expect(result, isNot(contains('@example')), reason: 'pad $pad');
      }
    });

    test(
      'a 43 character token and a phone on the boundary after the early replacements shrank',
      () {
        final token = 'aB3_-${'xY' * 19}';
        // Shrinks while cleaning and is shorter than 1100: the token and the phone reach the boundary.
        final filler = [for (var i = 0; i < 20; i++) 'Authorization: Bearer abcdefghijklmnop$i']
            .join(' ');
        expect(filler.length, lessThan(rawTextLimit - 100));
        for (var pad = 0; pad < rawTextLimit - filler.length; pad++) {
          final result = line('$filler ${'z' * pad} $token +992 900 12 34 56 $token');
          expect(result, isNot(contains('aB3_-xY')), reason: 'pad $pad');
          expect(result, isNot(contains('+992 900')), reason: 'pad $pad');
        }
      },
    );

    test(
      'an emoji on the boundary: the raw text is shorter than the limit, the tail still drops',
      () {
        const tail = r'C:\Users\John Smith';
        final squeeze = [
          for (var i = 0; i < 15; i++) 'Bearer abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG',
        ].join(' ');
        final pad = 'z' * (rawTextLimit - 1 - squeeze.length - 1 - tail.length);
        final message = '$squeeze $pad$tail😀x\\AppData';
        expect(message.codeUnitAt(rawTextLimit - 1), inInclusiveRange(0xD800, 0xDBFF));
        expect(line(message), isNot(contains('Smith')));
      },
    );

    test('a short line keeps its ending', () {
      expect(line('failure in order 15'), endsWith('failure in order 15'));
    });
  });
}
