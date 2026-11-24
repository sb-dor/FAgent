import 'dart:io';

import 'package:flutter_code_agent/_core/pub_workspace/pub_workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late String root;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pub_workspace_test');
    root = tmp.path;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  void write(String path, String content) {
    final file = File(p.join(root, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void flutterApp(String folder, String name, {bool main = true}) {
    write('$folder/pubspec.yaml', 'name: $name\ndependencies:\n  flutter:\n    sdk: flutter\n');
    if (main) write('$folder/lib/main.dart', 'void main() {}');
  }

  void dartPackage(String folder, String name) {
    write('$folder/pubspec.yaml', 'name: $name\ndependencies:\n  path: ^1.0.0\n');
  }

  List<String> folders(List<WorkspaceMember> members) => members.map((m) => m.folder).toList();

  void cafeLayout() {
    write('pubspec.yaml', 'name: cafe_workspace\nworkspace:\n  - apps/*\n  - packages/*\n');
    flutterApp('apps/desktop', 'cafe_desktop');
    dartPackage('apps/server', 'cafe_server');
    write('apps/server/lib/main.dart', 'void main() {}');
    dartPackage('packages/core', 'core');
  }

  test('cafe_pos-like layout is a monorepo', () {
    cafeLayout();
    expect(isPubMonorepo(root), isTrue);
    expect(folders(workspaceMembers(root)), ['apps/desktop', 'apps/server', 'packages/core']);
    expect(folders(runnableApps(root)), ['apps/desktop']);
    expect(workspacePackageName(root), 'cafe_workspace');
    final desktop = workspaceMembers(root).first;
    expect(desktop.packageName, 'cafe_desktop');
    expect(desktop.isFlutter, isTrue);
    expect(desktop.hasMain, isTrue);
  });

  test('one-app project with packages/ui is not a monorepo', () {
    write('pubspec.yaml', 'name: app\nworkspace:\n  - packages/ui\n');
    Directory(p.join(root, 'lib')).createSync();
    dartPackage('packages/ui', 'ui');
    expect(isPubMonorepo(root), isFalse);
  });

  test('no workspace key is not a monorepo', () {
    write('pubspec.yaml', 'name: app\n');
    expect(isPubMonorepo(root), isFalse);
  });

  test('no pubspec is not a monorepo', () {
    expect(isPubMonorepo(root), isFalse);
    expect(workspaceMembers(root), isEmpty);
    expect(workspacePackageName(root), isNull);
  });

  test('explicit member list', () {
    write('pubspec.yaml', 'name: w\nworkspace:\n  - apps/desktop\n  - packages/core\n');
    flutterApp('apps/desktop', 'desktop');
    dartPackage('packages/core', 'core');
    expect(isPubMonorepo(root), isTrue);
    expect(folders(workspaceMembers(root)), ['apps/desktop', 'packages/core']);
  });

  test('stray entries are not members', () {
    cafeLayout();
    Directory(p.join(root, 'apps/notes')).createSync();
    write('apps/.DS_Store', 'x');
    expect(folders(workspaceMembers(root)), ['apps/desktop', 'apps/server', 'packages/core']);
  });

  test('unreadable member pubspec is skipped', () {
    cafeLayout();
    write('apps/broken/pubspec.yaml', 'name: [unclosed\n  : :');
    expect(folders(workspaceMembers(root)), ['apps/desktop', 'apps/server', 'packages/core']);
  });

  test('flutter app without main is not runnable', () {
    write('pubspec.yaml', 'name: w\nworkspace:\n  - apps/*\n');
    flutterApp('apps/a', 'a', main: false);
    expect(runnableApps(root), isEmpty);
  });
}
