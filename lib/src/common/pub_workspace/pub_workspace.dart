import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// {@template workspace_member}
/// A package listed in the `workspace:` of a pub workspace root.
/// {@endtemplate}
@immutable
final class WorkspaceMember {
  /// {@macro workspace_member}
  const WorkspaceMember({
    required this.folder,
    required this.packageName,
    required this.isFlutter,
    required this.hasMain,
  });

  /// Folder relative to the workspace root, with `/` separators.
  final String folder;

  /// `name:` of the member's `pubspec.yaml`.
  final String packageName;

  /// Whether `dependencies` lists `flutter` (`sdk: flutter`).
  final bool isFlutter;

  /// Whether `lib/main.dart` exists.
  final bool hasMain;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceMember &&
      other.folder == folder &&
      other.packageName == packageName &&
      other.isFlutter == isFlutter &&
      other.hasMain == hasMain;

  @override
  int get hashCode => Object.hash(folder, packageName, isFlutter, hasMain);

  @override
  String toString() => 'WorkspaceMember($folder, $packageName)';
}

/// Whether [root] is a pub workspace root without an app of its own: its
/// `pubspec.yaml` has a `workspace:` key and there is no `lib/` directory.
bool isPubMonorepo(String root) {
  final pubspec = _readYaml(p.join(root, 'pubspec.yaml'));
  if (pubspec == null || pubspec['workspace'] is! YamlList) return false;
  return !Directory(p.join(root, 'lib')).existsSync();
}

/// `name:` of the root `pubspec.yaml`, or `null` when it is missing or unreadable.
String? workspacePackageName(String root) {
  final name = _readYaml(p.join(root, 'pubspec.yaml'))?['name'];
  return name is String ? name : null;
}

/// Members of the workspace at [root], sorted by folder.
///
/// Each `workspace:` entry is a path or a glob with `*` in one segment. Folders
/// without a readable `pubspec.yaml` are skipped.
List<WorkspaceMember> workspaceMembers(String root) {
  final workspace = _readYaml(p.join(root, 'pubspec.yaml'))?['workspace'];
  if (workspace is! YamlList) return const [];
  final folders = <String>{};
  for (final entry in workspace) {
    if (entry is! String) continue;
    folders.addAll(_expand(root, entry.split('/').where((s) => s.isNotEmpty && s != '.').toList()));
  }
  final members = <WorkspaceMember>[];
  for (final folder in folders) {
    final member = _member(root, folder);
    if (member != null) members.add(member);
  }
  members.sort((a, b) => a.folder.compareTo(b.folder));
  return members;
}

/// Members under `apps/` that are Flutter packages with a `lib/main.dart`.
List<WorkspaceMember> runnableApps(String root) => [
  for (final member in workspaceMembers(root))
    if (member.folder.startsWith('apps/') && member.isFlutter && member.hasMain) member,
];

Iterable<String> _expand(String root, List<String> segments) {
  var current = <String>[''];
  for (final segment in segments) {
    final next = <String>[];
    for (final base in current) {
      if (segment.contains('*')) {
        final dir = Directory(p.join(root, base));
        if (!dir.existsSync()) continue;
        final pattern = RegExp('^${segment.split('*').map(RegExp.escape).join('[^/]*')}\$');
        try {
          for (final entity in dir.listSync(followLinks: false)) {
            final name = p.basename(entity.path);
            if (entity is Directory && pattern.hasMatch(name)) {
              next.add(base.isEmpty ? name : '$base/$name');
            }
          }
        } on FileSystemException {
          continue;
        }
      } else {
        next.add(base.isEmpty ? segment : '$base/$segment');
      }
    }
    current = next;
  }
  return current;
}

WorkspaceMember? _member(String root, String folder) {
  final dir = p.joinAll([root, ...folder.split('/')]);
  final pubspec = _readYaml(p.join(dir, 'pubspec.yaml'));
  final name = pubspec?['name'];
  if (pubspec == null || name is! String) return null;
  final dependencies = pubspec['dependencies'];
  return WorkspaceMember(
    folder: folder,
    packageName: name,
    isFlutter: dependencies is YamlMap && dependencies.containsKey('flutter'),
    hasMain: File(p.join(dir, 'lib', 'main.dart')).existsSync(),
  );
}

YamlMap? _readYaml(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final doc = loadYaml(file.readAsStringSync());
    return doc is YamlMap ? doc : null;
  } on Object {
    return null;
  }
}
