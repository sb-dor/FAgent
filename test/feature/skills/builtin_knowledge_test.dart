import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/feature/skills/data/builtin_knowledge.dart';
import 'package:flutter_code_agent/src/feature/skills/data/frontmatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the app ships its built-in skills and rules', (tester) async {
    final files = await tester.runAsync(() => AssetBuiltinKnowledge(bundle: rootBundle).load());

    expect(
      files!.keys,
      containsAll(<String>[
        'skills/feature-architecture/SKILL.md',
        'skills/feature-architecture/templates/controller.dart',
        'skills/feature-architecture/templates/repository.dart',
        'skills/drift-migration/SKILL.md',
        'skills/pub-freshness/SKILL.md',
        'skills/widget-test/SKILL.md',
        'rules/architecture.md',
        'rules/package-freshness.md',
        'rules/localization.md',
      ]),
    );

    final skills = files.keys.where((key) => key.endsWith('/SKILL.md'));
    final rules = files.keys.where((key) => key.startsWith('rules/'));
    expect(skills, hasLength(4));
    expect(rules, hasLength(3));

    for (final key in skills) {
      final fields = parseFrontmatter(files[key]!)?.fields;
      expect(fields, isNotNull, reason: '$key has no frontmatter');
      expect(fields!['name'], key.split('/')[1], reason: key);
      expect(fields['description'], isNotEmpty, reason: key);
    }
    for (final key in rules) {
      final fields = parseFrontmatter(files[key]!)?.fields;
      expect(fields, isNotNull, reason: '$key has no frontmatter');
      expect(fields!['name'], key.substring('rules/'.length, key.length - '.md'.length));
      expect(fields['description'], isNotEmpty, reason: key);
    }
  });

  testWidgets('the result is cached', (tester) async {
    final knowledge = AssetBuiltinKnowledge(bundle: rootBundle);
    final first = await tester.runAsync(knowledge.load);
    final second = await tester.runAsync(knowledge.load);
    expect(identical(first, second), isTrue);
  });
}
