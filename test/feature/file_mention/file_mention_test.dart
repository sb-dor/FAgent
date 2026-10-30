import 'dart:io';

import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/file_mention/data/project_files_repository.dart';
import 'package:flutter_code_agent/src/feature/file_mention/models/file_mention.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mentionQueryAt', () {
    test('finds the mention right before the cursor', () {
      expect(mentionQueryAt('fix @lib/ma', 11), (start: 4, query: 'lib/ma'));
      expect(mentionQueryAt('@', 1), (start: 0, query: ''));
    });

    test('ignores text that is not a mention', () {
      expect(mentionQueryAt('mail me@host', 12), isNull);
      expect(mentionQueryAt('@done and more', 14), isNull);
      expect(mentionQueryAt('@a', 5), isNull);
    });
  });

  test('searchFiles ranks name prefixes, then names, paths and letters in order', () {
    const files = <String>[
      'lib/src/feature/chat/widgets/chat_screen.dart',
      'lib/src/my_chat.dart',
      'docs/chat/README.md',
      'lib/c_h_a_t.dart',
      'pubspec.yaml',
    ];

    expect(searchFiles(files, 'chat'), <String>[
      'lib/src/feature/chat/widgets/chat_screen.dart',
      'lib/src/my_chat.dart',
      'docs/chat/README.md',
      'lib/c_h_a_t.dart',
    ]);
    expect(searchFiles(files, 'PUB'), <String>['pubspec.yaml']);
    expect(searchFiles(files, '', limit: 2), hasLength(2));
  });

  test('mentionedFiles keeps known paths once, in order', () {
    expect(
      mentionedFiles('see @b.dart and @a.dart, again @b.dart and @nope.dart', <String>{
        'a.dart',
        'b.dart',
      }),
      <String>['b.dart', 'a.dart'],
    );
  });

  test('mentionedFiles takes the longest known path, with spaces or @ in it', () {
    const files = <String>{'lib/a', 'lib/a b.dart', 'ios/Runner/Icon-App-20x20@2x.png'};

    expect(
      mentionedFiles('fix @lib/a b.dart and @ios/Runner/Icon-App-20x20@2x.png.', files),
      <String>['lib/a b.dart', 'ios/Runner/Icon-App-20x20@2x.png'],
    );
    expect(mentionedFiles('@lib/a', files), <String>['lib/a']);
    expect(mentionedFiles('@lib/abc', files), isEmpty);
  });

  test('resourceLinks point at absolute file URIs', () {
    expect(resourceLinks('/work/my app', <String>['lib/main.dart']), <Map<String, Object?>>[
      <String, Object?>{
        'type': 'resource_link',
        'uri': 'file:///work/my%20app/lib/main.dart',
        'name': 'main.dart',
      },
    ]);
  });

  group('ProjectFilesRepositoryImpl', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('project_files');
      for (final path in <String>[
        'lib/main.dart',
        'build/out.txt',
        '.dart_tool/state.json',
        'pubspec.yaml',
      ]) {
        File('${root.path}/$path').createSync(recursive: true);
      }
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('a folder without git is walked, skipping build output', () async {
      final repository = ProjectFilesRepositoryImpl(
        environment: const ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'}),
      );

      expect(await repository.list(root.path), <String>['lib/main.dart', 'pubspec.yaml']);
    });

    test('a git repository lists tracked and untracked files without ignored ones', () async {
      File('${root.path}/.gitignore').writeAsStringSync('build/\n.dart_tool/\n');
      final init = await Process.run('git', <String>['init', '-q', root.path]);
      expect(init.exitCode, 0);
      final repository = ProjectFilesRepositoryImpl(environment: await ShellEnvironment.resolve());

      expect(await repository.list(root.path), <String>[
        '.gitignore',
        'lib/main.dart',
        'pubspec.yaml',
      ]);
    });

    test('mentions that lead out of the project through a link are dropped', () async {
      final outside = Directory.systemTemp.createTempSync('outside');
      addTearDown(() => outside.deleteSync(recursive: true));
      File('${outside.path}/id_rsa').createSync();
      Link('${root.path}/key').createSync('${outside.path}/id_rsa');
      Link('${root.path}/main_link.dart').createSync('lib/main.dart');
      final repository = ProjectFilesRepositoryImpl(
        environment: const ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'}),
      );

      expect(
        await repository.insideProject(root.path, <String>[
          'lib/main.dart',
          'key',
          'main_link.dart',
          'gone.dart',
        ]),
        <String>['lib/main.dart', 'main_link.dart'],
      );
    });

    test('the walk never follows a link out of the project', () {
      final outside = Directory.systemTemp.createTempSync('outside');
      addTearDown(() => outside.deleteSync(recursive: true));
      File('${outside.path}/secret.txt').createSync();
      Link('${root.path}/linked').createSync(outside.path);

      expect(ProjectFilesRepositoryImpl.walk(root.path), isNot(contains('linked/secret.txt')));
    });
  });
}
