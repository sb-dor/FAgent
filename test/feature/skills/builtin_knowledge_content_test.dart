@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_code_agent/src/feature/skills/data/frontmatter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Checks the files under `assets/knowledge/` on disk: the set of built-in rules and skills, their
/// frontmatter, the size of the rules (they all go into the agent's system prompt) and that the
/// code templates compile.
void main() {
  final knowledge = Directory('assets/knowledge');
  final rulesDirectory = Directory(p.join(knowledge.path, 'rules'));
  final skillsDirectory = Directory(p.join(knowledge.path, 'skills'));

  final ruleFiles = rulesDirectory.listSync().whereType<File>().toList();
  final skillDirectories = skillsDirectory.listSync().whereType<Directory>().toList();
  String name(FileSystemEntity entity) => p.basenameWithoutExtension(entity.path);

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

  test('the built-in skills are the expected set', () {
    expect(skillDirectories.map((directory) => p.basename(directory.path)).toSet(), <String>{
      'feature-architecture',
      'repository-streams',
      'paginated-controller',
      'controller-patterns',
      'dependency-injection',
      'drift-migration',
      'widget-test',
      'pub-freshness',
    });
  });

  test('every rule has frontmatter with its name and a description', () {
    for (final file in ruleFiles) {
      final fields = parseFrontmatter(file.readAsStringSync())?.fields;
      expect(fields, isNotNull, reason: '${file.path} has no frontmatter');
      expect(fields!['name'], name(file), reason: file.path);
      expect(fields['description'], isNotEmpty, reason: file.path);
    }
  });

  test('every skill has frontmatter with its folder name, a description and when_to_use', () {
    for (final directory in skillDirectories) {
      final file = File(p.join(directory.path, 'SKILL.md'));
      expect(file.existsSync(), isTrue, reason: '${directory.path} has no SKILL.md');
      final fields = parseFrontmatter(file.readAsStringSync())?.fields;
      expect(fields, isNotNull, reason: '${file.path} has no frontmatter');
      expect(fields!['name'], p.basename(directory.path), reason: file.path);
      expect(fields['description'], isNotEmpty, reason: file.path);
      expect(fields['when_to_use'], isNotEmpty, reason: file.path);
      expect(fields['version'], isNotEmpty, reason: file.path);
    }
  });

  test('the rules stay within the system prompt budget', () {
    final totalRuleBytes = ruleFiles.fold<int>(0, (sum, file) => sum + file.lengthSync());
    expect(totalRuleBytes, lessThanOrEqualTo(8192));
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

  test('every skill mentions the templates it ships', () {
    for (final directory in skillDirectories) {
      final templates = Directory(p.join(directory.path, 'templates'));
      if (!templates.existsSync()) continue;
      final skill = File(p.join(directory.path, 'SKILL.md')).readAsStringSync();
      for (final template in templates.listSync().whereType<File>()) {
        expect(skill, contains(p.basename(template.path)), reason: template.path);
      }
    }
  });

  test(
    'the code templates compile',
    () async {
      final fixture = Directory('test/fixtures/knowledge_templates');
      final lib = Directory(p.join(fixture.path, 'lib'));
      if (lib.existsSync()) lib.deleteSync(recursive: true);
      lib.createSync();
      addTearDown(() => lib.deleteSync(recursive: true));

      // Templates of all skills share one flat folder, so their file names must be unique.
      final seen = <String>{};
      for (final directory in skillDirectories) {
        final templates = Directory(p.join(directory.path, 'templates'));
        if (!templates.existsSync()) continue;
        for (final file in templates.listSync().whereType<File>()) {
          final fileName = p.basename(file.path);
          expect(seen.add(fileName), isTrue, reason: 'Duplicate template name $fileName');
          file.copySync(p.join(lib.path, fileName));
        }
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
