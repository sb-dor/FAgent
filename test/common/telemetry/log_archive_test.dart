import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_code_agent/src/common/telemetry/log_archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildLogArchive: a zip with the files and their text', () {
    final bytes = buildLogArchive({'a.log': 'line 1', 'b/info.txt': 'version 1'});
    final zip = ZipDecoder().decodeBytes(bytes);
    expect(zip.files.map((f) => f.name), unorderedEquals(['a.log', 'b/info.txt']));
    expect(utf8.decode(zip.findFile('a.log')!.content), 'line 1');
    expect(utf8.decode(zip.findFile('b/info.txt')!.content), 'version 1');
  });
}
