import 'dart:convert';

import 'package:archive/archive.dart';

/// A zip of "file name → text" pairs (UTF-8).
List<int> buildLogArchive(Map<String, String> files) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    final bytes = utf8.encode(value);
    archive.addFile(ArchiveFile(key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}
