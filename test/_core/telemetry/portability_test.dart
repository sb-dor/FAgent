import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _prefix = 'package:flutter_code_agent/_core/telemetry/';

final RegExp _import = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

List<File> _dartFiles(String dir) => [
  for (final entity in Directory(dir).listSync(recursive: true))
    if (entity is File && entity.path.endsWith('.dart') && !entity.path.endsWith('.g.dart')) entity,
];

// The directives of [file] that break the portability of the telemetry module.
List<String> _violations(File file, {required bool allowPart}) {
  final result = <String>[];
  for (final match in _import.allMatches(file.readAsStringSync())) {
    final uri = match[1]!;
    final isPart = match[0]!.trimLeft().startsWith('part');
    if (isPart && allowPart) {
      continue;
    }
    if (uri.startsWith('package:flutter/')) {
      result.add('${file.path}: Flutter import $uri');
    } else if (uri.startsWith('package:flutter_code_agent/')) {
      if (!uri.startsWith(_prefix)) {
        result.add('${file.path}: import outside the module $uri');
      }
    } else if (!uri.startsWith('package:') && !uri.startsWith('dart:')) {
      result.add('${file.path}: relative import $uri');
    }
  }
  return result;
}

void main() {
  test('the module imports only itself and pub packages, no Flutter, no relative imports', () {
    final files = _dartFiles('lib/_core/telemetry');

    expect(files, isNotEmpty);
    expect([for (final f in files) ..._violations(f, allowPart: true)], isEmpty);
  });

  test('the tests of the module use only flutter_test, the module and pub packages', () {
    final files = _dartFiles('test/_core/telemetry');

    expect(files, isNotEmpty);
    final violations = <String>[];
    for (final file in files) {
      for (final match in _import.allMatches(file.readAsStringSync())) {
        final uri = match[1]!;
        if (uri.contains('test/support') || uri.contains('support/')) {
          violations.add('${file.path}: support helper $uri');
        }
      }
      violations.addAll(_violations(file, allowPart: false));
    }
    expect(violations, isEmpty);
  });
}
