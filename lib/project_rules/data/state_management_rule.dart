import 'dart:io';

import 'package:path/path.dart' as p;

/// The built-in rule of a project whose business logic is written with `package:control`.
const String controlRuleName = 'controllers';

/// The built-in rule of a project whose business logic is written with `package:bloc`.
const String blocRuleName = 'bloc';

/// The built-in rules of which a project gets one: the rule of its state management package.
const Set<String> stateManagementRuleNames = <String>{controlRuleName, blocRuleName};

/// The state management rule of the project at [root]: [blocRuleName] when a `pubspec.yaml` of it
/// (the root or a member in `apps/`) depends on `bloc` or `flutter_bloc` and none depends on
/// `control`, [controlRuleName] otherwise. A file that cannot be read counts as no dependency.
String stateManagementRuleOf(String root) {
  final pubspecs = <File>[
    File(p.join(root, 'pubspec.yaml')),
    if (Directory(p.join(root, 'apps')).existsSync())
      for (final app in Directory(p.join(root, 'apps')).listSync().whereType<Directory>())
        File(p.join(app.path, 'pubspec.yaml')),
  ];
  var bloc = false;
  for (final pubspec in pubspecs) {
    final String text;
    try {
      if (!pubspec.existsSync()) continue;
      text = pubspec.readAsStringSync();
    } on FileSystemException {
      continue;
    }
    if (_dependsOn(text, 'control')) return controlRuleName;
    bloc = bloc || _dependsOn(text, 'bloc') || _dependsOn(text, 'flutter_bloc');
  }
  return bloc ? blocRuleName : controlRuleName;
}

/// Whether [pubspec] lists [package] as a dependency: a `  <package>:` key indented under a
/// section.
bool _dependsOn(String pubspec, String package) =>
    RegExp('^\\s+${RegExp.escape(package)}:', multiLine: true).hasMatch(pubspec);
