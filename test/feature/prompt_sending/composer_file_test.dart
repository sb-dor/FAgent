import 'package:flutter_code_agent/src/feature/prompt_sending/models/composer_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const home = '/Users/avaz';

  group('label', () {
    test('a long name is cut in the middle, the home folder is ~', () {
      final label = composerFileLabel(
        '/Users/avaz/Desktop/Снимок экрана — 2026-11-04 в 15.53.33.heic',
        home: home,
      );

      expect(label, startsWith('~/Desktop/Снимок экрана'));
      expect(label, endsWith('15.53.33.heic'));
      expect(label, contains('…'));
      expect(label.split('/').last.length, lessThanOrEqualTo(composerFileNameLength));
    });

    test('a short name stays whole', () {
      expect(composerFileLabel('/Users/avaz/notes.txt', home: home), '~/notes.txt');
    });

    test('a path outside the home folder stays absolute', () {
      expect(composerFileLabel('/opt/data/a.csv', home: home), '/opt/data/a.csv');
    });

    test('a folder ends with /', () {
      expect(composerFileLabel('/Users/avaz/Downloads', home: home, folder: true), '~/Downloads/');
    });
  });

  group('badge', () {
    test('is the extension in capitals', () {
      expect(const ComposerFile(path: '/x/a.heic').badge, 'HEIC');
      expect(const ComposerFile(path: '/x/Report.Final.PDF').badge, 'PDF');
    });

    test('is null without an extension or for a folder', () {
      expect(const ComposerFile(path: '/x/Makefile').badge, isNull);
      expect(const ComposerFile(path: '/x/dir.v2', folder: true).badge, isNull);
    });
  });

  group('block', () {
    test('a file is a resource_link to its file URI', () {
      expect(const ComposerFile(path: '/Users/avaz/Desktop/a b.heic').toBlock(), <String, Object?>{
        'type': 'resource_link',
        'uri': 'file:///Users/avaz/Desktop/a%20b.heic',
        'name': 'a b.heic',
      });
    });

    test('a folder links with a trailing /', () {
      expect(
        const ComposerFile(path: '/Users/avaz/Downloads', folder: true).toBlock()['uri'],
        'file:///Users/avaz/Downloads/',
      );
    });

    test('fromUri reads a card back, a folder by its trailing /', () {
      expect(
        ComposerFile.fromUri('file:///Users/avaz/Desktop/a%20b.heic'),
        const ComposerFile(path: '/Users/avaz/Desktop/a b.heic'),
      );
      expect(
        ComposerFile.fromUri('file:///Users/avaz/Downloads/'),
        const ComposerFile(path: '/Users/avaz/Downloads', folder: true),
      );
      expect(ComposerFile.fromUri('https://example.com/a'), isNull);
    });
  });

  group('the cards of a sent message', () {
    test('are the links its text does not @mention', () {
      expect(
        attachedFiles('look at @lib/main.dart and these', <String>[
          'file:///work/app/lib/main.dart',
          'file:///Users/avaz/Desktop/shot.heic',
        ]),
        const <ComposerFile>[ComposerFile(path: '/Users/avaz/Desktop/shot.heic')],
      );
    });
  });
}
