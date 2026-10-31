import 'dart:convert';
import 'dart:io';

import 'package:flutter_code_agent/src/feature/permission_rules/data/permission_rules_repository.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/models/permission_rules_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late PermissionRulesRepositoryImpl repository;

  File settings() => File(p.join(root.path, '.claude', 'settings.local.json'));

  void writeSettings(String text) {
    settings().parent.createSync(recursive: true);
    settings().writeAsStringSync(text);
  }

  const original =
      '{"permissions":{"allow":["Bash(npm test:*)", 3, "WebFetch(domain:pub.dev)"],'
      ' "deny":["Bash(rm:*)"]},"env":{"A":"1"}}';

  setUp(() {
    root = Directory.systemTemp.createTempSync('permission_rules_test');
    repository = PermissionRulesRepositoryImpl();
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('rules', () {
    test('reads allow rules', () async {
      writeSettings(original);
      expect(await repository.rules(root.path), <String>[
        'Bash(npm test:*)',
        'WebFetch(domain:pub.dev)',
      ]);
    });

    test('no file is empty', () async {
      expect(await repository.rules(root.path), isEmpty);
    });

    test('no permissions or no allow is empty', () async {
      writeSettings('{"env":{"A":"1"}}');
      expect(await repository.rules(root.path), isEmpty);
      writeSettings('{"permissions":{"deny":["Bash(rm:*)"]}}');
      expect(await repository.rules(root.path), isEmpty);
    });

    test('broken file is unreadable', () async {
      writeSettings('{');
      await expectLater(
        repository.rules(root.path),
        throwsA(
          isA<PermissionRulesUnreadableException>().having((e) => e.path, 'path', settings().path),
        ),
      );
    });

    test('a file that is not an object is unreadable', () async {
      writeSettings('["Bash(npm test:*)"]');
      await expectLater(
        repository.rules(root.path),
        throwsA(isA<PermissionRulesUnreadableException>()),
      );
    });
  });

  group('remove', () {
    test('remove keeps everything else', () async {
      writeSettings(original);

      await repository.remove(root.path, 'Bash(npm test:*)');

      final text = settings().readAsStringSync();
      expect(text, endsWith('\n'));
      expect(
        jsonDecode(text),
        jsonDecode(
          '{"permissions":{"allow":[3,"WebFetch(domain:pub.dev)"],"deny":["Bash(rm:*)"]},'
          '"env":{"A":"1"}}',
        ),
      );
      expect((jsonDecode(text) as Map<String, Object?>).keys, <String>['permissions', 'env']);
      expect(settings().parent.listSync().map((e) => p.basename(e.path)), <String>[
        'settings.local.json',
      ]);
    });

    test('removes every copy of the rule', () async {
      writeSettings('{"permissions":{"allow":["a","b","a"]}}');
      await repository.remove(root.path, 'a');
      expect(await repository.rules(root.path), <String>['b']);
    });

    test('does nothing without the file or the rule', () async {
      await repository.remove(root.path, 'a');
      expect(settings().existsSync(), isFalse);
      expect(Directory(p.join(root.path, '.claude')).existsSync(), isFalse);

      writeSettings(original);
      await repository.remove(root.path, 'Bash(other)');
      expect(settings().readAsStringSync(), original);
    });

    test('a broken file is not touched', () async {
      writeSettings('{');
      await expectLater(
        repository.remove(root.path, 'a'),
        throwsA(isA<PermissionRulesUnreadableException>()),
      );
      expect(settings().readAsStringSync(), '{');
    });
  });
}
