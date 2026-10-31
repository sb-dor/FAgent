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

/// Why there is no `flutter` for [projectPath], in English: it goes into the `Flutter SDK not
/// found` error of a run, next to the output of `flutter`.
String flutterNotFoundMessage(String? projectPath) =>
    'There is no `flutter` on the PATH of the login shell. Install Flutter or add its bin folder '
    'to the PATH.';
