import 'package:flutter_code_agent/src/feature/code_view/widgets/code_quick_open.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const files = <String>[
    'README.md',
    'lib/main.dart',
    'lib/src/feature/main_screen.dart',
    'lib/src/domain.dart',
    'test/domain_test.dart',
    'lib/feature.dart',
  ];

  test('an empty query lists the files as they are', () {
    expect(quickOpenMatches(files, ''), files);
  });

  test('matches are case-insensitive substrings', () {
    expect(quickOpenMatches(files, 'DOMAIN'), <String>[
      'lib/src/domain.dart',
      'test/domain_test.dart',
    ]);
  });

  test('a name match ranks above a folder match', () {
    // lib/feature.dart matches by its name, main_screen.dart only by its folder.
    expect(quickOpenMatches(files, 'feature'), <String>[
      'lib/feature.dart',
      'lib/src/feature/main_screen.dart',
    ]);
  });

  test('at most 50 rows', () {
    final many = <String>[for (var i = 0; i < 80; i++) 'lib/file_$i.dart'];

    expect(quickOpenMatches(many, 'file'), hasLength(50));
  });
}
