import 'dart:convert';

import 'package:flutter_code_agent/src/common/telemetry/error_outbox.dart' show errorTypeName;
import 'package:flutter_code_agent/src/common/telemetry/redact.dart';

final RegExp _digits = RegExp(r'\d+');
final RegExp _uuid = RegExp(
  r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
);
final RegExp _hexToken = RegExp(r'\b[0-9a-fA-F]{8,}\b');
final RegExp _frameIndex = RegExp(r'^#\d+\s+');
final RegExp _framePosition = RegExp(r':\d+(?::\d+)?\)');

// The addresses of an AOT stack change from run to run; `…Instructions+0x…` stays.
final RegExp _absVirt = RegExp(r'\b(?:abs|virt)\s+[0-9a-fA-F]+\s*');

// The header of an obfuscated stack: pid, build_id and base addresses.
final RegExp _aotHeader = RegExp(r'^(?:\*\*\*|pid:|tid:|build_id|isolate_|vm_|os:|arch:|comp:)');

/// How many project frames go into the fingerprint.
const int fingerprintFrames = 5;

/// The fingerprint of an error: the type, the message with numbers replaced by `#`, and the first
/// [fingerprintFrames] frames of the project's stack, without line numbers. A frame is the
/// project's when it contains `package:<name>/` for a name in [projectPackages], or `+0x` (an AOT
/// frame). The same error with other numbers gives the same fingerprint.
String errorFingerprint(Object error, StackTrace stack, {required Set<String> projectPackages}) {
  final message = cleanForLog(error.toString())
      .replaceAll(_uuid, '#')
      .replaceAll(_hexToken, '#')
      .replaceAll(_digits, '#');
  final lines = stack
      .toString()
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !_aotHeader.hasMatch(l))
      .toList();
  final project = lines
      .where((l) => l.contains('+0x') || projectPackages.any((p) => l.contains('package:$p/')))
      .toList();
  final frames = (project.isEmpty ? lines : project)
      .take(fingerprintFrames)
      .map(
        (l) => l
            .replaceAll(_absVirt, '')
            .replaceFirst(_frameIndex, '')
            .replaceFirst(_framePosition, ')')
            .trim(),
      );
  return _hash('${errorTypeName(error)}\n$message\n${frames.join('\n')}');
}

// FNV-1a, 64 bits: a short key for a unique index.
String _hash(String text) {
  // The 64-bit constants are built from parts: a literal above 2^53 is not exact in JavaScript.
  var h = (0xcbf29ce4 << 32) | 0x84222325;
  for (final byte in utf8.encode(text)) {
    h ^= byte;
    h *= (1 << 40) | 0x1b3;
  }
  return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}
