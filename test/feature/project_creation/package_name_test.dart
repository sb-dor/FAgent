import 'package:flutter_code_agent/src/feature/project_creation/models/package_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('checkPackageName', () {
    test('accepts a valid name', () => expect(checkPackageName('avera_booking'), isNull));
    test('empty', () => expect(checkPackageName(''), PackageNameProblem.empty));
    for (final name in ['My-App', '1app', 'app.name', 'привет', 'app name', 'app\n']) {
      test(
        'invalid: ${name.trim()}',
        () => expect(checkPackageName(name), PackageNameProblem.invalid),
      );
    }
    for (final name in ['class', 'yield', 'abstract', 'with']) {
      test('keyword: $name', () => expect(checkPackageName(name), PackageNameProblem.keyword));
    }
    for (final name in ['collection', 'flutter', 'flutter_test', 'meta']) {
      test(
        'dependency: $name',
        () => expect(checkPackageName(name), PackageNameProblem.dependency),
      );
    }
  });

  group('suggestPackageName', () {
    test('lowercases and replaces dashes', () => expect(suggestPackageName('My-App'), 'my_app'));
    test('prefixes a leading digit', () => expect(suggestPackageName('1app'), '_1app'));
    test('replaces spaces', () => expect(suggestPackageName('Hello World'), 'hello_world'));
    test('drops other characters', () => expect(suggestPackageName('app.name!'), 'appname'));
    test('nothing valid is left', () {
      expect(suggestPackageName('---'), isNull);
      expect(suggestPackageName('!!!'), isNull);
      expect(suggestPackageName(''), isNull);
    });
    test('a keyword stays unusable', () => expect(suggestPackageName('Class'), isNull));
  });
}
