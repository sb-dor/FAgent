import 'package:flutter_code_agent/src/feature/skills/data/frontmatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseFrontmatter', () {
    test('reads name and description', () {
      final parsed = parseFrontmatter('---\nname: a\ndescription: "Does x: y"\n---\n# A\n');
      expect(parsed, isNotNull);
      expect(parsed!.fields, {'name': 'a', 'description': 'Does x: y'});
      expect(parsed.body, '# A\n');
    });

    test('no frontmatter is null', () {
      expect(parseFrontmatter('# Title'), isNull);
      expect(parseFrontmatter('---\nname: a\n'), isNull);
    });

    test('broken yaml throws', () {
      expect(() => parseFrontmatter('---\nname: [a\n---\n'), throwsA(isA<FrontmatterException>()));
    });

    test('a non-map frontmatter throws', () {
      expect(() => parseFrontmatter('---\n- a\n- b\n---\n'), throwsA(isA<FrontmatterException>()));
    });

    test('metadata.version is lifted', () {
      final parsed = parseFrontmatter('---\nname: a\nmetadata:\n  version: 1.3\n---\n');
      expect(parsed!.fields['version'], '1.3');
    });

    test('a top-level version wins over metadata.version', () {
      final parsed = parseFrontmatter('---\nname: a\nversion: 2\nmetadata:\n  version: 1.3\n---\n');
      expect(parsed!.fields['version'], '2');
    });

    test('folded description', () {
      final parsed = parseFrontmatter('---\nname: a\ndescription: >\n  one\n  two\n---\n');
      expect(parsed!.fields['description'], 'one two');
    });

    test('non-string values are converted to strings', () {
      final parsed = parseFrontmatter('---\nname: a\ncount: 3\n---\n');
      expect(parsed!.fields['count'], '3');
    });
  });

  group('writeFrontmatter', () {
    test('round trip', () {
      final text = writeFrontmatter({'name': 'a', 'description': 'x: y'}, 'Body\n');
      final parsed = parseFrontmatter(text);
      expect(parsed, isNotNull);
      expect(parsed!.fields, {'name': 'a', 'description': 'x: y'});
      expect(parsed.body, 'Body\n');
    });
  });
}
