import 'dart:io' as io;

import 'package:path/path.dart' as p;

/// Finds the `flutter` executable for [projectPath].
///
/// Prefers the project's own fvm SDK (`.fvm/flutter_sdk/bin/flutter`), then
/// falls back to `which('flutter')`. Returns `null` when neither exists.
String? flutterExecutableFor(String? projectPath, {required String? Function(String name) which}) {
  if (projectPath != null) {
    final fvm = p.join(projectPath, '.fvm', 'flutter_sdk', 'bin', 'flutter');
    if (io.File(fvm).existsSync()) return fvm;
  }
  return which('flutter');
}
