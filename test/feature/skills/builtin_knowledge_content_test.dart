@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_code_agent/src/feature/skills/data/frontmatter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Checks the files under `assets/knowledge/` on disk: the set of built-in rules, their
/// frontmatter, that they carry the skills merged into them, and that their code examples compile.
void main() {
  final knowledge = Directory('assets/knowledge');
  final rulesDirectory = Directory(p.join(knowledge.path, 'rules'));

  final ruleFiles = rulesDirectory.listSync().whereType<File>().toList();
  String name(FileSystemEntity entity) => p.basenameWithoutExtension(entity.path);
  String rule(String name) => File(p.join(rulesDirectory.path, '$name.md')).readAsStringSync();

  /// The `## ` headings of every skill merged into a rule, by rule, as the skills had them.
  const mergedHeadings = <String, List<String>>{
    'controllers': <String>[
      'Single responsibility',
      'Mutation features (creation, deletion)',
      'Multiple controllers in one feature',
      'Template',
      'Convenience getters on the state',
      'Triggering `paginate` from the widget',
      'Non-paginated lists',
      'Refinements, where the screen earns them',
    ],
    'dependencies': <String>[
      'Global: `Dependencies` and `DependenciesScope`',
      'Feature level: config widgets',
      'Reaching feature dependencies',
      'Interfaces and constructor injection',
    ],
    'repositories': <String>[
      'Pattern 1: `onListen` / `onCancel` (lazy, resource-safe)',
      'Pattern 2: `async Future` wrapper (simpler)',
      'One-shot helpers',
      'Steps',
      'Checks',
    ],
    'architecture': <String>[
      'Project structure',
      'Layers and dependency direction',
      'List / screen feature',
      'Creation / update feature',
      'Deletion feature',
      'By-id loader feature',
      'Models and JSON converters',
      'Repositories',
      'Local database tables',
      'Localization',
      'Reusable widgets',
      'Widgets',
      'Steps for a new feature',
    ],
    'package-freshness': <String>['Steps', 'Notes'],
    'widgets': <String>['Steps', 'Rules'],
  };

  /// The template files the skills shipped; each is now a `// file:` block of a rule.
  const exampleFiles = <String>{
    'example_creation_controller.dart',
    'example_deletion_controller.dart',
    'example_deletion_dialog.dart',
    'example_mutation_repositories.dart',
    'dependencies.dart',
    'example.dart',
    'example_config_widget.dart',
    'example_controller.dart',
    'example_data_controller.dart',
    'example_json_converter.dart',
    'example_repository.dart',
    'example_widget.dart',
    'local_pagination_util.dart',
    'product.dart',
    'products_controller.dart',
    'products_data_controller.dart',
    'products_list_widget.dart',
    'products_repository.dart',
    'example_stream_repository.dart',
  };

  /// The `dart` blocks of every rule that start with `// file: <name>.dart`, by name.
  Map<String, String> examples() {
    final blocks = <String, String>{};
    final fence = RegExp(r'```dart\n// file: ([\w.]+\.dart)\n([\s\S]*?)\n```');
    for (final file in ruleFiles) {
      for (final match in fence.allMatches(file.readAsStringSync())) {
        expect(blocks.containsKey(match.group(1)), isFalse, reason: 'Duplicate ${match.group(1)}');
        blocks[match.group(1)!] = '${match.group(2)}\n';
      }
    }
    return blocks;
  }

  test('the built-in rules are the expected set', () {
    expect(ruleFiles.map(name).toSet(), <String>{
      'architecture',
      'controllers',
      'repositories',
      'dependencies',
      'widgets',
      'localization',
      'package-freshness',
      'generated-files',
    });
  });

  test('no built-in skills ship', () {
    expect(Directory(p.join(knowledge.path, 'skills')).existsSync(), isFalse);
    expect(File('pubspec.yaml').readAsStringSync(), isNot(contains('assets/knowledge/skills')));
  });

  test('every merged rule keeps the sections of its skills', () {
    for (final MapEntry(key: name, value: headings) in mergedHeadings.entries) {
      final text = rule(name);
      for (final heading in headings) {
        expect(
          RegExp('^#{2,3} ${RegExp.escape(heading)}\$', multiLine: true).hasMatch(text),
          isTrue,
          reason: '$name.md has no "$heading" section',
        );
      }
    }
  });

  test('every example of the skills is a block of a rule', () {
    expect(examples().keys.toSet(), exampleFiles);
  });

  test('every rule has frontmatter with its name and a description', () {
    for (final file in ruleFiles) {
      final fields = parseFrontmatter(file.readAsStringSync())?.fields;
      expect(fields, isNotNull, reason: '${file.path} has no frontmatter');
      expect(fields!['name'], name(file), reason: file.path);
      expect(fields['description'], isNotEmpty, reason: file.path);
    }
  });

  test('no built-in file carries this repository\'s own overrides', () {
    const forbidden = <String>['Desktop only', 'No ApiClient', 'flutter_code_agent'];
    for (final entity in knowledge.listSync(recursive: true).whereType<File>()) {
      final text = entity.readAsStringSync();
      for (final phrase in forbidden) {
        expect(text, isNot(contains(phrase)), reason: '${entity.path} contains "$phrase"');
      }
    }
  });

  test(
    'the code examples compile',
    () async {
      final fixture = Directory('test/fixtures/knowledge_templates');
      final lib = Directory(p.join(fixture.path, 'lib'));
      if (lib.existsSync()) lib.deleteSync(recursive: true);
      lib.createSync();
      addTearDown(() => lib.deleteSync(recursive: true));

      final seen = <String>{};
      for (final MapEntry(key: fileName, value: code) in examples().entries) {
        seen.add(fileName);
        File(p.join(lib.path, fileName)).writeAsStringSync(code);
      }
      expect(seen, isNotEmpty);

      Future<void> run(String executable, List<String> arguments) async {
        final result = await Process.run(executable, arguments, workingDirectory: fixture.path);
        expect(
          result.exitCode,
          0,
          reason: '$executable ${arguments.join(' ')}\n${result.stdout}\n${result.stderr}',
        );
      }

      await run('flutter', <String>['pub', 'get']);
      await run('dart', <String>['run', 'build_runner', 'build', '--delete-conflicting-outputs']);
      await run('dart', <String>['analyze', '--fatal-infos']);
    },
    tags: 'flutter',
    timeout: const Timeout(Duration(minutes: 10)),
    skip: Platform.environment['FLUTTER_RUN_TEST'] == '1'
        ? false
        : 'Compiles the templates with the real toolchain; set FLUTTER_RUN_TEST=1',
  );
}
