import 'package:flutter_code_agent/src/feature/chat/models/tool_row_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const root = '/Users/me/proj';

  group('relativeToRoot', () {
    test('cuts the project root off a path inside it', () {
      expect(relativeToRoot('$root/lib/a.dart', root), 'lib/a.dart');
      expect(relativeToRoot('$root/lib/a.dart', '$root/'), 'lib/a.dart');
    });

    test(
      'keeps a path outside the root, a sibling with the same prefix and any path without one',
      () {
        expect(relativeToRoot('/etc/hosts', root), '/etc/hosts');
        expect(relativeToRoot('$root-other/a.dart', root), '$root-other/a.dart');
        expect(relativeToRoot('$root/a.dart', null), '$root/a.dart');
      },
    );
  });

  group('toolRowLabel', () {
    test('splits a path into name and the folder relative to the root', () {
      final label = toolRowLabel(title: 'Edit', path: '$root/lib/src/a.dart', projectRoot: root);
      expect((label.name, label.folder), ('a.dart', 'lib/src/'));
    });

    test('a file in the root has no folder', () {
      final label = toolRowLabel(title: 'Edit', path: '$root/a.dart', projectRoot: root);
      expect((label.name, label.folder), ('a.dart', null));
    });

    test('a path outside the root keeps its absolute folder', () {
      final label = toolRowLabel(title: 'Read', path: '/etc/hosts', projectRoot: root);
      expect((label.name, label.folder), ('hosts', '/etc/'));
    });

    test('a title that ends with the path keeps only the verb', () {
      expect(
        toolRowLabel(
          title: 'Write $root/hello.txt',
          path: '$root/hello.txt',
          projectRoot: root,
        ).title,
        'Write',
      );
      expect(
        toolRowLabel(title: 'Read lib/a.dart', path: '$root/lib/a.dart', projectRoot: root).title,
        'Read',
      );
      expect(
        toolRowLabel(title: 'Edit a.dart', path: '$root/lib/a.dart', projectRoot: root).title,
        'Edit',
      );
    });

    test('a title that is only the path is dropped', () {
      expect(
        toolRowLabel(title: '$root/hello.txt', path: '$root/hello.txt', projectRoot: root).title,
        isNull,
      );
    });

    test('a title without the path stays whole', () {
      expect(
        toolRowLabel(title: 'Run flutter test', path: '$root/a.dart', projectRoot: root).title,
        'Run flutter test',
      );
    });

    test('without a path there is only the title', () {
      final label = toolRowLabel(title: 'ls -la', path: null, projectRoot: root);
      expect((label.title, label.name, label.folder), ('ls -la', null, null));
    });
  });
}
