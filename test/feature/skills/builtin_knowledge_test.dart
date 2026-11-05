import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/feature/skills/data/builtin_knowledge.dart';
import 'package:flutter_code_agent/src/feature/skills/data/frontmatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the app ships its built-in rules and no skills', (tester) async {
    final files = await tester.runAsync(() => AssetBuiltinKnowledge(bundle: rootBundle).load());

    expect(
      files!.keys,
      unorderedEquals(<String>[
        'rules/architecture.md',
        'rules/controllers.md',
        'rules/repositories.md',
        'rules/dependencies.md',
        'rules/widgets.md',
        'rules/localization.md',
        'rules/package-freshness.md',
        'rules/generated-files.md',
      ]),
    );

    final rules = files.keys.where((key) => key.startsWith('rules/'));
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
