import 'package:flutter_code_agent/src/common/telemetry/clip.dart';
import 'package:flutter_code_agent/src/common/telemetry/redact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a long string without secrets is cleaned in linear time', () {
    // The log of a device is accepted up to 5 MB: a solid string must not hang the app.
    final watch = Stopwatch()..start();
    final text = 'a' * 9000;

    expect(redactSecrets(text), text);
    expect(redactSecrets('${'x' * 9000}@'), '${'x' * 9000}@');

    // A guard against catastrophic backtracking, not a speed test: wide for a loaded CI.
    expect(watch.elapsedMilliseconds, lessThan(5000));
  });

  test('solid data of megabytes is clipped, neighbouring lines stay whole', () {
    final watch = Stopwatch()..start();
    final huge = 'a' * (5 * 1024 * 1024);

    final result = redactSecrets('first token=abc\n$huge\nthird');

    expect(result, startsWith('first token=[REDACTED]\n'));
    expect(result, endsWith('…\nthird'));
    expect(result.length, lessThan(logClipLength + 100));
    expect(watch.elapsedMilliseconds, lessThan(20000));
  });

  test('a field name with a prefix is still cleaned', () {
    expect(redactSecrets('deviceToken=abc123'), 'deviceToken=[REDACTED]');
    expect(redactSecrets('{"apiKey": "1234-5678"}'), '{"apiKey": "[REDACTED]"}');
    expect(
      redactSecrets('writes a.b@example.com, phone +992 900 12 34 56'),
      'writes [REDACTED], phone [REDACTED]',
    );
  });

  group('secret formats', () {
    String r(String s) => redactSecrets(s);

    test('Bearer, Authorization with a scheme and without', () {
      expect(r('Authorization: Bearer abc.def'), 'Authorization: Bearer [REDACTED]');
      expect(r('Authorization: Basic dXNlcjpwYXNz'), 'Authorization: Basic [REDACTED]');
      expect(r('Authorization: abc123token'), 'Authorization: [REDACTED]');
      expect(r('authorization=Digest k9x8y7z6w5'), 'authorization=Digest [REDACTED]');
    });

    test('field names: quotes, camelCase, header, query, underscores', () {
      expect(r('{"key": "v1"}'), '{"key": "[REDACTED]"}');
      expect(r('deviceKey=abc'), 'deviceKey=[REDACTED]');
      expect(r('X-Api-Key: abc123'), 'X-Api-Key: [REDACTED]');
      expect(r('GET /v1/x?token=abc&b=1'), 'GET /v1/x?token=[REDACTED]&b=1');
      expect(r('pin_code=4821'), 'pin_code=[REDACTED]');
      expect(r('pinHash=9f86d0'), 'pinHash=[REDACTED]');
    });

    test('a quoted value with an escaped quote, an unclosed quote', () {
      expect(r(r'{"password": "ab\"cd", "x": 1}'), '{"password": "[REDACTED]", "x": 1}');
      expect(r('password="abc def'), contains(redactedMark));
      expect(r('password="abc def'), isNot(contains('abc')));
    });

    test('phone: fields in any format, text only with a plus', () {
      expect(r('phone: 900123456'), 'phone: [REDACTED]');
      expect(r('{"customerPhone":"8 (900) 123-45-67"}'), '{"customerPhone":"[REDACTED]"}');
      expect(r('tel=900 12 34 56'), 'tel=[REDACTED]');
      expect(r('called +992 900 12 34 56'), 'called [REDACTED]');
    });

    test('phone: telephone, cellphone, PascalCase; microphone and headphone stay', () {
      expect(r('telephone: 900123456'), 'telephone: [REDACTED]');
      expect(r('cellphone=900123456'), 'cellphone=[REDACTED]');
      expect(r('{"HomePhone":"900123456"}'), '{"HomePhone":"[REDACTED]"}');
      expect(r('CustomerPhone: 900123456'), 'CustomerPhone: [REDACTED]');
      expect(r('microphone: on'), 'microphone: on');
      expect(r('headphone=wired'), 'headphone=wired');
    });

    test('leaves plain text, fingerprints, numbers, amounts and dates alone', () {
      for (final text in [
        'Device is offline',
        'receipt 000123 for 1500.50',
        'delivered 2026-11-12 10:15:03',
        'fingerprint 3A:7F:19:C4:AB:00:12:EE:5D:90:41:BC',
        'shipping: 5',
        'hotel: Marriott',
      ]) {
        expect(r(text), text, reason: text);
      }
    });
  });

  group('agent keys', () {
    String r(String s) => redactSecrets(s);

    test('every key format in free text becomes the mark', () {
      for (final key in [
        'sk-ant-api03-AbCdEf0123456789AbCdEf0123456789',
        'sk-proj-AbCdEf0123456789AbCdEf01',
        'sk-AbCdEf0123456789AbCdEf0123',
        'ghp_AbCdEf0123456789AbCdEf0123456789AbCd',
        'gho_AbCdEf0123456789AbCdEf0123456789AbCd',
        'github_pat_11ABCDEFG0123456789_abcdefghijklmnop',
        'AIzaSyA-AbCdEf0123456789AbCdEf0123456',
        'xoxb-1234567890-abcdefghij',
      ]) {
        expect(r('agent said $key and stopped'), 'agent said [REDACTED] and stopped', reason: key);
        expect(r(key), redactedMark, reason: key);
      }
    });

    test('look-alikes stay', () {
      for (final text in [
        'task-manager',
        'sk-ip',
        'ghp',
        'xox',
        'ghp_short',
        'gho_abc',
        'sk-ant-short',
        'sk-proj-short',
        'sk-short',
        'AIzaShort',
        'github_pat_short',
        'xoxb-123',
        'disk-usage-report-for-the-whole-machine',
      ]) {
        expect(r(text), text, reason: text);
      }
    });

    test('a key glued to a longer word is not cut out of it', () {
      expect(r('mysk-AbCdEf0123456789AbCdEf0123'), 'mysk-AbCdEf0123456789AbCdEf0123');
    });
  });

  group('server secrets in free text', () {
    String r(String s) => redactSecrets(s);
    const uuid = '3f2b8c1e-9d4a-4e6b-8a17-5c0d2e9f1a34';
    final secret43 = 'aB3_-${'xY' * 19}'; // exactly 43

    test('a separate token of 43 base64url characters', () {
      expect(secret43.length, 43);
      expect(r('session $secret43.'), 'session [REDACTED].');
      expect(r('("$secret43")'), '("[REDACTED]")');
    });

    test('false positives: a single UUID, sha256, plain words', () {
      for (final text in [
        uuid,
        'sha256 ${'a1b2c3d4' * 8}',
        'hex43 ${'ab12cd34ef' * 4}abc',
        'license L-2026-0001',
        'Internationalization_and_localization_support_of_x',
        'order 3f2b8c1e-9d4a-4e6b-8a17-5c0d2e9f1a34 created',
      ]) {
        expect(r(text), text, reason: text);
      }
    });

    test('a 44 character token is not cut into parts', () {
      final long = '${secret43}Q';
      expect(r('x $long y'), 'x $long y');
    });

    test('a second cleaning does not change the result', () {
      final once = r('$secret43 and Bearer abc and sk-AbCdEf0123456789AbCdEf0123');
      expect(r(once), once);
    });

    test('a long identifier of letters (drift) is not a token', () {
      const name = 'CashSnapshotAccountsTableAnnotationCo'; // 37
      const id43 = '${name}mposer'; // 43 characters, letters only
      expect(id43.length, 43);
      expect(r('type $id43 not found'), 'type $id43 not found');
    });
  });

  group('user paths', () {
    String r(String s) => redactSecrets(s);

    test('a name with a space, case, escaped JSON, Program Files stays', () {
      expect(r(r'C:\Users\John Smith\AppData\x'), r'C:\Users\[REDACTED]\AppData\x');
      expect(r(r'c:\users\avaz\x'), r'c:\users\[REDACTED]\x');
      expect(r(r'{"p":"C:\\Users\\avaz\\x"}'), r'{"p":"C:\\Users\\[REDACTED]\\x"}');
      expect(r(r'C:\Program Files\App\x'), r'C:\Program Files\App\x');
      expect(r('/Users/avaz could not be opened'), '/Users/[REDACTED] could not be opened');
    });

    test('the user name on Windows, macOS and Linux', () {
      expect(r(r'open C:\Users\Avaz\AppData\x.db'), r'open C:\Users\[REDACTED]\AppData\x.db');
      expect(r('/Users/avaz/Library/x'), '/Users/[REDACTED]/Library/x');
      expect(r('file:///home/avaz/.cache/y'), 'file:///home/[REDACTED]/.cache/y');
    });

    test('look-alikes stay: packages, other paths', () {
      for (final text in [
        '#0 f (package:my_app/home/home_page.dart:10:5)',
        '/usr/home/x',
        r'C:\Program Files\Users\x',
        'path /Usersx/a',
      ]) {
        expect(r(text), text, reason: text);
      }
    });
  });

  group('time limits', () {
    for (final (name, text) in [
      ('letters in a row', 'a' * 100000),
      ('base64url', 'Ab-_' * 25000),
      ('a1.', 'a1.' * 33000),
    ]) {
      test('100 000 characters ($name) are cleaned without backtracking', () {
        final watch = Stopwatch()..start();
        redactSecrets(clipForLog(text));
        // Backtracking takes minutes here; the bound is wide for a loaded CI.
        expect(watch.elapsedMilliseconds, lessThan(2000));
      });
    }

    test('clipForLog cuts to 16 KB, leaves short text, never splits a surrogate pair', () {
      expect(clipForLog('abc'), 'abc');
      final long = clipForLog('я' * 20000);
      expect(long.length, lessThanOrEqualTo(logClipLength + 1));
      expect(long, endsWith('…'));
      // The boundary falls in the middle of an emoji.
      for (var pad = 0; pad < 2; pad++) {
        final clipped = clipForLog('${'x' * (logClipLength - 1 + pad)}${'😀' * 10}');
        final unit = clipped.codeUnits[clipped.length - 2];
        expect(unit >= 0xD800 && unit <= 0xDBFF, isFalse, reason: 'pad $pad');
      }
    });
  });

  test('a second cleaning does not change the result', () {
    for (final text in [
      'password=abc',
      'token: "x y"',
      'Authorization: Bearer abc',
      'phone=+992 900 12 34 56',
      'a@b.com Bearer abc12345',
    ]) {
      final once = redactSecrets(text);
      expect(redactSecrets(once), once, reason: text);
      expect(once, isNot(contains(']]')), reason: text);
    }
    expect(redactSecrets('password=[REDACTED]'), 'password=[REDACTED]');
  });

  test('an unclosed quote cleans the value to the end of the line', () {
    final result = redactSecrets('password="abc def\nnext line');
    expect(result, isNot(contains('abc')));
    expect(result, isNot(contains('def')));
    expect(result, endsWith('\nnext line'));
  });

  test('phone fields phone, tel, mobile and camelCase; microphone, headphone stay', () {
    for (final text in [
      'phone=+7 900',
      'user_phone: 88001',
      'tel=123',
      'mobile=555 66',
      'userPhone=1 2 3',
      'homePhoneNumber: "9 9"',
    ]) {
      final result = redactSecrets(text);
      expect(result, contains(redactedMark), reason: text);
      expect(result.replaceAll(RegExp(r'\d'), ''), result, reason: text);
    }
    for (final text in ['microphone=on', 'headphone=3', 'hotel=Ritz 5', 'telegram=ok']) {
      expect(redactSecrets(text), text, reason: text);
    }
  });

  test('clipping a line does not split a surrogate pair', () {
    final line = '${'a' * (logClipLength - 1)}😀 tail';
    final result = redactSecrets(line + 'z' * 10);
    expect(
      result.codeUnits.where((u) => u >= 0xD800 && u <= 0xDBFF).length,
      result.codeUnits.where((u) => u >= 0xDC00 && u <= 0xDFFF).length,
    );
  });
}
