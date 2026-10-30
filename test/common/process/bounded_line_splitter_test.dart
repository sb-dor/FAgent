import 'dart:convert';

import 'package:flutter_code_agent/src/common/process/bounded_line_splitter.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<String>> _split(List<List<int>> chunks, {int maxLineBytes = 2000}) =>
    Stream<List<int>>.fromIterable(chunks)
        .transform(BoundedLineSplitter(maxLineBytes: maxLineBytes))
        .toList();

void main() {
  test('splits lines across chunks and handles CRLF and a trailing line', () async {
    final lines = await _split(<List<int>>[utf8.encode('one\r\ntw'), utf8.encode('o\nthree')]);
    expect(lines, <String>['one', 'two', 'three']);
  });

  test('keeps multi-byte characters split between chunks', () async {
    final bytes = utf8.encode('привет\n');
    final lines = await _split(<List<int>>[bytes.sublist(0, 3), bytes.sublist(3)]);
    expect(lines, <String>['привет']);
  });

  test('truncates a 10 MB line without newline instead of buffering it', () async {
    final chunk = List<int>.filled(1 << 20, 0x61);
    final lines = await _split(<List<int>>[
      for (var i = 0; i < 10; i++) chunk,
      utf8.encode('\nok\n'),
    ]);
    expect(lines, hasLength(2));
    expect(lines.first, '${'a' * 2000}…');
    expect(lines.last, 'ok');
  });

  test('strips ANSI escape sequences', () async {
    final lines = await _split(<List<int>>[utf8.encode('\x1B[33mwarn\x1B[0m done\n')]);
    expect(lines, <String>['warn done']);
  });

  test('ring buffer keeps the newest items', () {
    final buffer = RingBuffer<int>(3);
    for (var i = 0; i < 5; i++) {
      buffer.add(i);
    }
    expect(buffer.items, <int>[2, 3, 4]);
  });
}
