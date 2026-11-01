import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as p;

/// Finds the `flutter` executable for [projectPath].
///
/// A project that pins a Flutter version with fvm ([fvmPinOf]) runs on its own fvm SDK
/// (`.fvm/flutter_sdk/bin/flutter`) or not at all: `null` when that SDK is not installed, rather
/// than another version from the `PATH`. Without a pin, and without a project, it is
/// `which('flutter')`, `null` when there is none.
String? flutterExecutableFor(String? projectPath, {required String? Function(String name) which}) {
  if (projectPath != null) {
    final fvm = p.join(projectPath, '.fvm', 'flutter_sdk', 'bin', 'flutter');
    if (io.File(fvm).existsSync()) return fvm;
    if (fvmPinOf(projectPath) != null) return null;
  }
  return which('flutter');
}

/// The Flutter version [projectPath] pins with fvm: `.fvmrc` (`flutter`), else the older
/// `.fvm/fvm_config.json` (`flutterSdkVersion`). `null` when the project has neither file; a
/// [version] of `null` when the file is there but does not name one.
///
/// The files are tiny and read synchronously, so a widget test in fake async can run this.
({String? version})? fvmPinOf(String projectPath) {
  for (final (path, key) in <(String, String)>[
    (p.join(projectPath, '.fvmrc'), 'flutter'),
    (p.join(projectPath, '.fvm', 'fvm_config.json'), 'flutterSdkVersion'),
  ]) {
    final file = io.File(path);
    if (!file.existsSync()) continue;
    try {
      final json = jsonDecode(file.readAsStringSync());
      final value = json is Map<String, Object?> ? json[key] : null;
      return (version: value is String && value.isNotEmpty ? value : null);
    } on io.FileSystemException {
      return (version: null);
    } on FormatException {
      return (version: null);
    }
  }
  return null;
}

/// Why there is no `flutter` for [projectPath], in English: it goes into the `Flutter SDK not
/// found` error of a run, next to the output of `flutter`.
String flutterNotFoundMessage(String? projectPath) {
  final pin = projectPath == null ? null : fvmPinOf(projectPath);
  if (pin != null) {
    final version = pin.version == null ? '' : ' ${pin.version}';
    return 'This project pins Flutter$version with fvm, but it is not installed. '
        'Run `fvm install` in the project folder.';
  }
  return 'There is no `flutter` on the PATH of the login shell. Install Flutter or add its bin '
      'folder to the PATH.';
}

/// The Flutter SDK folder that [flutterExecutable] (`<SDK>/bin/flutter`, found by
/// [flutterExecutableFor]) belongs to, with symlinks resolved. `null` when the file does not
/// exist or has no `bin/dart` next to it (a wrapper script rather than the SDK's own `flutter`).
String? flutterSdkRootOf(String flutterExecutable) {
  final String resolved;
  try {
    resolved = io.File(flutterExecutable).resolveSymbolicLinksSync();
  } on io.FileSystemException {
    return null;
  }
  final bin = p.dirname(resolved);
  if (p.basename(bin) != 'bin') return null;
  final root = p.dirname(bin);
  return io.File(p.join(root, 'bin', 'dart')).existsSync() ? root : null;
}
