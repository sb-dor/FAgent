import 'dart:convert';

import 'package:path/path.dart' as p;

/// {@template code_package_labels}
/// Short names of files outside the project, for read-only tabs: `package:flutter/…` for a file
/// of a package the project uses (from its `.dart_tool/package_config.json`), `dart:core/…` for
/// the Dart SDK's libraries, the path with `~` for anything else.
/// {@endtemplate}
final class CodePackageLabels {
  /// No packages known: Dart SDK names and paths only.
  const CodePackageLabels.none({required this._home}) : _packages = const <(String, String)>[];

  CodePackageLabels._(this._home, this._packages);

  /// Reads [packageConfigJson]; a relative `rootUri` resolves against [configDir] (the
  /// `.dart_tool` folder). JSON that cannot be read gives [CodePackageLabels.none].
  factory CodePackageLabels.parse(
    String packageConfigJson, {
    required String configDir,
    required String home,
  }) {
    final Object? json;
    try {
      json = jsonDecode(packageConfigJson);
    } on FormatException {
      return CodePackageLabels.none(home: home);
    }
    final packages = <(String, String)>[];
    final entries = json is Map ? json['packages'] : null;
    final base = Uri.directory(configDir);
    for (final entry in entries is List ? entries : const <Object?>[]) {
      if (entry is! Map) continue;
      final name = entry['name'];
      final rootUri = entry['rootUri'];
      if (name is! String || rootUri is! String) continue;
      final root = base.resolve(rootUri.endsWith('/') ? rootUri : '$rootUri/');
      final lib = root.resolve('${entry['packageUri'] ?? ''}');
      if (!lib.isScheme('file')) continue;
      packages.add((name, p.normalize(lib.toFilePath())));
    }
    // The deepest folder first: a package inside another one's folder wins.
    packages.sort((a, b) => b.$2.length.compareTo(a.$2.length));
    return CodePackageLabels._(home, packages);
  }

  final String _home;

  /// Package name and its library folder.
  final List<(String, String)> _packages;

  static const String _sdkLib = '/dart-sdk/lib/';

  /// The short name of [path].
  String labelFor(String path) {
    for (final (name, lib) in _packages) {
      if (p.isWithin(lib, path))
        return 'package:$name/${p.posix.joinAll(p.split(p.relative(path, from: lib)))}';
    }
    final sdk = path.indexOf(_sdkLib);
    if (sdk >= 0) return 'dart:${path.substring(sdk + _sdkLib.length)}';
    if (_home.isNotEmpty && p.isWithin(_home, path))
      return p.join('~', p.relative(path, from: _home));
    return path;
  }
}
