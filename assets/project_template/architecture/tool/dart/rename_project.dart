// Renames the project: its package name, its organization (the start of the application and
// bundle ids) and its description, in the Dart code and the platform projects.
//
//   dart run tool/dart/rename_project.dart --name=shop_app --organization=com.company
//   dart run tool/dart/rename_project.dart --name=shop_app --description="Orders and payments"
//
// The current values are read from the project: the name and description from pubspec.yaml, the
// organization from the Android application id (or pass --from-organization=com.example). Commit
// first: every file it changes is then visible in `git diff`, and a mistake is one `git checkout`.
// It sorts the imports again at the end; afterwards run `flutter clean`, `flutter pub get` and
// `flutter analyze`.

import 'dart:io';

/// Folders that are never touched: generated, vendored or version control.
const Set<String> _skippedFolders = <String>{
  '.git',
  '.dart_tool',
  '.idea',
  '.vscode',
  'build',
  'Pods',
  'coverage',
};

/// The text files that can name the package or the organization.
const Set<String> _textExtensions = <String>{
  '.dart',
  '.yaml',
  '.json',
  '.arb',
  '.md',
  '.gradle',
  '.kts',
  '.xml',
  '.kt',
  '.java',
  '.swift',
  '.plist',
  '.pbxproj',
  '.xcscheme',
  '.xcconfig',
  '.entitlements',
  '.cc',
  '.cpp',
  '.h',
  '.rc',
  '.txt',
  '.html',
  '.properties',
};

void main(List<String> arguments) {
  final options = <String, String>{};
  for (final argument in arguments) {
    final match = RegExp(r'^--([a-z-]+)=(.*)$').firstMatch(argument);
    if (match == null) return _usage('Unknown argument: $argument');
    options[match.group(1)!] = match.group(2)!;
  }
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) return _usage('Run it from the project root (no pubspec.yaml here).');
  final pubspecText = pubspec.readAsStringSync();

  final oldName = _field(pubspecText, 'name');
  if (oldName == null) return _usage('pubspec.yaml has no name.');
  final newName = options['name'] ?? oldName;
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(newName)) {
    return _usage('--name must be lowercase letters, digits and underscores: $newName');
  }

  final oldOrganization = options['from-organization'] ?? _organization(oldName);
  final newOrganization = options['organization'] ?? oldOrganization;
  if (newOrganization != oldOrganization && oldOrganization == null) {
    return _usage('Cannot read the current organization: pass --from-organization=...');
  }
  final organization = RegExp(r'^[a-zA-Z]\w*(\.[a-zA-Z]\w*)+$');
  if (newOrganization != null && !organization.hasMatch(newOrganization)) {
    return _usage('--organization must look like com.company: $newOrganization');
  }

  // The longest first, so `com.example.my_app` is replaced as a whole before `my_app`.
  final replacements = <(String, String)>[
    if (oldOrganization != null && newOrganization != null) ...[
      ('$oldOrganization.$oldName', '$newOrganization.$newName'),
      ('$oldOrganization.${_camel(oldName)}', '$newOrganization.${_camel(newName)}'),
      (oldOrganization, newOrganization),
    ],
    ('package:$oldName/', 'package:$newName/'),
    (oldName, newName),
    (_camel(oldName), _camel(newName)),
  ].where((pair) => pair.$1 != pair.$2).toList(growable: false);

  final changed = <String>[];
  for (final file in _textFiles(Directory.current)) {
    final text = file.readAsStringSync();
    var next = text;
    for (final (from, to) in replacements) {
      next = next.replaceAll(from, to);
    }
    if (next == text) continue;
    file.writeAsStringSync(next);
    changed.add(file.path);
  }

  final description = options['description'];
  if (description != null) {
    final text = pubspec.readAsStringSync().replaceFirst(
      RegExp(r'^description:.*$', multiLine: true),
      'description: "${description.replaceAll('"', r'\"')}"',
    );
    pubspec.writeAsStringSync(text);
  }

  final moved = _moveAndroidSources(oldOrganization, oldName, newOrganization, newName);
  stdout.writeln('Changed ${changed.length} files; moved ${moved.length} source folders.');

  // Imports of the new package name sort differently (`directives_ordering`).
  final fix = Process.runSync(Platform.resolvedExecutable, const <String>[
    'fix',
    '--apply',
    '--code=directives_ordering',
  ]);
  if (fix.exitCode != 0) stderr.write(fix.stderr);
  stdout.writeln('Now run: flutter clean && flutter pub get && flutter analyze');
}

/// Prints the problem and how to call the script, and sets the exit code of a wrong command line.
void _usage(String problem) {
  stderr
    ..writeln(problem)
    ..writeln(
      'Usage: dart run tool/dart/rename_project.dart --name=new_name '
      '[--organization=com.company] [--description="..."] [--from-organization=com.example]',
    );
  exitCode = 64;
}

/// The value of a top-level [key] in pubspec.yaml.
String? _field(String pubspec, String key) {
  final match = RegExp('^$key:\\s*(.+)\$', multiLine: true).firstMatch(pubspec);
  return match?.group(1)?.trim().replaceAll(RegExp('^["\']|["\']\$'), '');
}

/// The organization from the Android application id `<organization>.<name>`.
String? _organization(String name) {
  for (final path in const ['android/app/build.gradle.kts', 'android/app/build.gradle']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final match = RegExp(r'''applicationId\s*=?\s*["']([\w.]+)["']''')
        .firstMatch(file.readAsStringSync());
    final id = match?.group(1);
    if (id != null && id.endsWith('.$name')) return id.substring(0, id.length - name.length - 1);
  }
  return null;
}

/// `my_app` as `myApp`: the form `flutter create` uses in the iOS and macOS bundle ids.
String _camel(String name) {
  final parts = name.split('_');
  return parts.first +
      parts
          .skip(1)
          .map((part) => part.isEmpty ? '' : part[0].toUpperCase() + part.substring(1))
          .join();
}

/// Every text file of the project, skipping generated folders and this script.
Iterable<File> _textFiles(Directory directory) sync* {
  for (final entity in directory.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
    if (entity is Directory) {
      if (_skippedFolders.contains(name)) continue;
      yield* _textFiles(entity);
    } else if (entity is File) {
      if (name == 'rename_project.dart') continue;
      final dot = name.lastIndexOf('.');
      if (dot >= 0 && _textExtensions.contains(name.substring(dot))) yield entity;
    }
  }
}

/// Moves `android/app/src/<set>/{kotlin,java}/<old/org>/<old_name>` to the new package path, so
/// the folders match the `package` line again. Returns the folders it moved.
List<String> _moveAndroidSources(
  String? oldOrganization,
  String oldName,
  String? newOrganization,
  String newName,
) {
  final moved = <String>[];
  if (oldOrganization == null || newOrganization == null) return moved;
  final sources = Directory('android/app/src');
  if (!sources.existsSync()) return moved;
  final from = [...oldOrganization.split('.'), oldName].join('/');
  final to = [...newOrganization.split('.'), newName].join('/');
  if (from == to) return moved;
  for (final set in sources.listSync().whereType<Directory>()) {
    for (final language in const ['kotlin', 'java']) {
      final old = Directory('${set.path}/$language/$from');
      if (!old.existsSync()) continue;
      final target = Directory('${set.path}/$language/$to');
      target.parent.createSync(recursive: true);
      old.renameSync(target.path);
      moved.add(target.path);
      // Remove the old organization folders that are now empty.
      var parent = old.parent;
      while (parent.path != '${set.path}/$language' && parent.listSync().isEmpty) {
        parent.deleteSync();
        parent = parent.parent;
      }
    }
  }
  return moved;
}
