import 'dart:convert';

import 'package:flutter_code_agent/src/feature/code_view/data/code_package_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const root = '/Users/me/app';
  const home = '/Users/me';
  final config = jsonEncode(<String, Object?>{
    'configVersion': 2,
    'packages': <Object?>[
      <String, Object?>{
        'name': 'flutter',
        'rootUri': 'file:///sdk/packages/flutter',
        'packageUri': 'lib/',
      },
      <String, Object?>{'name': 'app', 'rootUri': '../', 'packageUri': 'lib/'},
    ],
  });
  final labels = CodePackageLabels.parse(config, configDir: '$root/.dart_tool', home: home);

  test('a file of a package gets its package: name', () {
    expect(
      labels.labelFor('/sdk/packages/flutter/lib/src/widgets/container.dart'),
      'package:flutter/src/widgets/container.dart',
    );
  });

  test('a relative rootUri resolves against the .dart_tool folder', () {
    expect(labels.labelFor('$root/lib/main.dart'), 'package:app/main.dart');
  });

  test('a Dart SDK file gets its dart: name', () {
    expect(labels.labelFor('/x/bin/cache/dart-sdk/lib/core/int.dart'), 'dart:core/int.dart');
  });

  test('anything else is its path with ~ for home', () {
    expect(labels.labelFor('/Users/me/other.dart'), '~/other.dart');
    expect(labels.labelFor('/opt/other.dart'), '/opt/other.dart');
  });

  test('none and unreadable JSON fall back to paths', () {
    expect(const CodePackageLabels.none(home: home).labelFor('/Users/me/a.dart'), '~/a.dart');
    expect(
      CodePackageLabels.parse(
        'not json',
        configDir: '$root/.dart_tool',
        home: home,
      ).labelFor('$root/lib/main.dart'),
      '~/app/lib/main.dart',
    );
  });
}
