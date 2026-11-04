import 'dart:convert';
import 'dart:io';

import 'package:flutter_code_agent/src/feature/app_run/models/build_mode.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/launch_config.dart';
import 'package:path/path.dart' as p;

/// What reading the `launch.json` of a project gave.
sealed class LaunchConfigs {
  const LaunchConfigs();
}

/// The project has no `launch.json`.
final class LaunchConfigsMissing extends LaunchConfigs {
  /// Creates the result.
  const LaunchConfigsMissing();
}

/// Why a `launch.json` cannot be read.
enum LaunchUnreadableKind {
  /// The text is not JSON (even with comments and trailing commas allowed).
  invalidJson,

  /// The JSON is not an object.
  notAnObject,

  /// `configurations` is there but is not a list.
  noConfigurationsList,

  /// The file system refused, or the file is not text.
  cannotRead,
}

/// The file exists but cannot be read.
final class LaunchConfigsUnreadable extends LaunchConfigs {
  /// Creates the result.
  const LaunchConfigsUnreadable(this.kind, [this.detail]);

  /// What is wrong.
  final LaunchUnreadableKind kind;

  /// The message of the parser ([LaunchUnreadableKind.invalidJson]) or of the file system
  /// ([LaunchUnreadableKind.cannotRead]); `null` for the other kinds.
  final String? detail;
}

/// The file was read.
final class LaunchConfigsRead extends LaunchConfigs {
  /// Creates the result.
  const LaunchConfigsRead(this.configs);

  /// The Dart launch configurations in the order of the file.
  final List<LaunchConfig> configs;
}

/// The content of the `launch.json` the app creates.
const String _emptyLaunchJson = '{"version": "0.2.0", "configurations": []}\n';

const String _workspaceFolder = r'${workspaceFolder}';

final RegExp _variable = RegExp(r'\$\{[^}]*\}');

/// `<projectRoot>/.vscode/launch.json`.
String launchJsonPath(String projectRoot) => p.join(projectRoot, '.vscode', 'launch.json');

/// Reads and parses the `launch.json` of [projectRoot].
Future<LaunchConfigs> readLaunchConfigs(String projectRoot) async {
  final file = File(launchJsonPath(projectRoot));
  try {
    if (!file.existsSync()) return const LaunchConfigsMissing();
    return parseLaunchConfigs(await file.readAsString(), projectRoot: projectRoot);
  } on FileSystemException catch (error) {
    return LaunchConfigsUnreadable(LaunchUnreadableKind.cannotRead, error.message);
  } on FormatException catch (error) {
    // A file that is not UTF-8.
    return LaunchConfigsUnreadable(LaunchUnreadableKind.cannotRead, error.message);
  }
}

/// Creates `.vscode/launch.json` with no configurations. Does nothing when the file exists.
Future<void> createLaunchJson(String projectRoot) async {
  final file = File(launchJsonPath(projectRoot));
  await file.parent.create(recursive: true);
  try {
    await file.create(exclusive: true);
  } on PathExistsException {
    return;
  }
  await file.writeAsString(_emptyLaunchJson);
}

/// Parses the text of a `launch.json` (JSON with comments and trailing commas) into the Dart
/// launch configurations it holds. Configurations of other types and `attach` requests are left
/// out; a configuration the app cannot run keeps its place with [LaunchConfig.unsupported] set.
LaunchConfigs parseLaunchConfigs(String text, {required String projectRoot}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(_dropTrailingCommas(_stripComments(text)));
  } on FormatException catch (error) {
    return LaunchConfigsUnreadable(LaunchUnreadableKind.invalidJson, error.message);
  }
  if (decoded is! Map) return const LaunchConfigsUnreadable(LaunchUnreadableKind.notAnObject);
  final entries = decoded['configurations'];
  if (entries == null) return const LaunchConfigsRead(<LaunchConfig>[]);
  if (entries is! List)
    return const LaunchConfigsUnreadable(LaunchUnreadableKind.noConfigurationsList);
  final root = _trimSlashes(projectRoot);
  return LaunchConfigsRead(<LaunchConfig>[
    for (final entry in entries)
      if (entry is Map && entry['type'] == 'dart' && entry['request'] == 'launch')
        ?_parseConfig(entry, root),
  ]);
}

/// The configuration of [entry], or `null` when it has no name.
LaunchConfig? _parseConfig(Map<Object?, Object?> entry, String root) {
  final name = entry['name'];
  if (name is! String) return null;

  final program = entry['program'];
  final cwd = entry['cwd'];
  final args = <String>[
    for (final key in const <String>['args', 'toolArgs'])
      if (entry[key] case final List<Object?> list)
        for (final arg in list)
          if (arg is String) _substitute(arg, root),
  ];
  final environment = <String, String>{
    if (entry['env'] case final Map<Object?, Object?> env)
      for (final MapEntry(:key, :value) in env.entries)
        if (key is String && value != null) key: _substitute('$value', root),
  };
  final deviceId = entry['deviceId'];
  final flutterMode = entry['flutterMode'];
  final preLaunchTask = entry['preLaunchTask'];

  final split = _splitFlags(args);
  return LaunchConfig(
    name: name,
    target: program is String && program.isNotEmpty
        ? _relativeTarget(_substitute(program, root), root)
        : 'lib/main.dart',
    flavor: split.flavor,
    dartDefines: split.defines,
    extraArgs: split.rest.map(_quote).join(' '),
    deviceId: deviceId is String && deviceId.isNotEmpty ? deviceId : split.deviceId,
    mode: _modeOf(flutterMode) ?? split.mode,
    environment: environment,
    unsupported: _unsupportedReason(
      <String?>[
        if (program is String) program,
        if (cwd is String) cwd,
        for (final key in const <String>['args', 'toolArgs'])
          if (entry[key] case final List<Object?> list) ...list.whereType<String>(),
        if (entry['env'] case final Map<Object?, Object?> env) ...env.values.map((v) => '$v'),
        if (deviceId is String) deviceId,
      ],
      cwd is String ? cwd : null,
      root,
    ),
    hasPreLaunchTask: preLaunchTask is String && preLaunchTask.isNotEmpty,
  );
}

/// The first `${…}` variable other than `${workspaceFolder}` among [values], or a `cwd` that is
/// not the project folder (as the file spells it, with `${workspaceFolder}` still in it); `null`
/// when the configuration can run.
LaunchUnsupported? _unsupportedReason(Iterable<String?> values, String? cwd, String root) {
  for (final value in values) {
    if (value == null) continue;
    for (final match in _variable.allMatches(value)) {
      if (match[0] != _workspaceFolder) return LaunchUnsupportedVariable(match[0]!);
    }
  }
  if (cwd != null && cwd.isNotEmpty && !_isProjectFolder(_substitute(cwd, root), root)) {
    return LaunchCwdOutsideProject(cwd);
  }
  return null;
}

/// Whether [cwd] (already free of `${workspaceFolder}`) names [root], relative or absolute, with
/// `.`, `..` and trailing slashes resolved.
bool _isProjectFolder(String cwd, String root) =>
    p.equals(p.normalize(p.join(root, cwd)), p.normalize(root));

String _substitute(String value, String root) => value.replaceAll(_workspaceFolder, root);

/// [path] relative to [root] when it is inside it.
String _relativeTarget(String path, String root) {
  if (path.startsWith('$root/')) return path.substring(root.length + 1);
  return path.startsWith('./') ? path.substring(2) : path;
}

/// [path] without trailing slashes (the root `/` stays as it is).
String _trimSlashes(String path) {
  var end = path.length;
  while (end > 1 && path[end - 1] == '/') {
    end--;
  }
  return path.substring(0, end);
}

BuildMode? _modeOf(Object? name) => switch (name) {
  'debug' => BuildMode.debug,
  'profile' => BuildMode.profile,
  'release' => BuildMode.release,
  _ => null,
};

typedef _Flags = ({
  String? flavor,
  List<String> defines,
  String? deviceId,
  BuildMode? mode,
  List<String> rest,
});

/// Takes the flags the app has its own controls for out of [args]; the others stay in `rest`, in
/// order. A flag that expects a value but is the last argument stays in `rest`.
_Flags _splitFlags(List<String> args) {
  String? flavor;
  String? deviceId;
  BuildMode? mode;
  final defines = <String>[];
  final rest = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    final equals = arg.startsWith('--') ? arg.indexOf('=') : -1;
    final flag = equals > 0 ? arg.substring(0, equals) : arg;
    final inline = equals > 0 ? arg.substring(equals + 1) : null;
    switch (flag) {
      case '--debug' || '--profile' || '--release' when inline == null:
        mode = _modeOf(flag.substring(2));
      case '--flavor' || '--dart-define' || '-d' || '--device-id':
        final String value;
        if (inline != null) {
          value = inline;
        } else if (i + 1 < args.length) {
          value = args[++i];
        } else {
          rest.add(arg);
          continue;
        }
        switch (flag) {
          case '--flavor':
            flavor = value;
          case '--dart-define':
            defines.add(value);
          default:
            deviceId = value;
        }
      default:
        rest.add(arg);
    }
  }
  return (flavor: flavor, defines: defines, deviceId: deviceId, mode: mode, rest: rest);
}

/// [arg] as one word for `splitArgs`: left as it is when it needs no quoting.
String _quote(String arg) {
  if (arg.isNotEmpty && !arg.contains(RegExp('[\\s\'"\\\\]'))) return arg;
  return '"${arg.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

/// [text] without `//` and `/* */` comments. Comment markers inside strings stay.
String _stripComments(String text) {
  final out = StringBuffer();
  var i = text.startsWith('﻿') ? 1 : 0;
  while (i < text.length) {
    final char = text[i];
    if (char == '"') {
      final end = _stringEnd(text, i);
      out.write(text.substring(i, end));
      i = end;
    } else if (char == '/' && i + 1 < text.length && text[i + 1] == '/') {
      while (i < text.length && text[i] != '\n') {
        i++;
      }
    } else if (char == '/' && i + 1 < text.length && text[i + 1] == '*') {
      final close = text.indexOf('*/', i + 2);
      i = close < 0 ? text.length : close + 2;
      // A comment separates tokens like a space does.
      out.write(' ');
    } else {
      out.write(char);
      i++;
    }
  }
  return out.toString();
}

/// [text] without a comma that is followed only by whitespace and then `]` or `}`. Commas inside
/// strings stay. Comments must already be stripped.
String _dropTrailingCommas(String text) {
  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final char = text[i];
    if (char == '"') {
      final end = _stringEnd(text, i);
      out.write(text.substring(i, end));
      i = end;
    } else if (char == ',') {
      var next = i + 1;
      while (next < text.length && text[next].trim().isEmpty) {
        next++;
      }
      if (next < text.length && (text[next] == ']' || text[next] == '}')) {
        i++;
      } else {
        out.write(char);
        i++;
      }
    } else {
      out.write(char);
      i++;
    }
  }
  return out.toString();
}

/// The index just past the string that opens with the quote at [start]; the end of [text] when
/// the string is not closed.
int _stringEnd(String text, int start) {
  var i = start + 1;
  while (i < text.length) {
    if (text[i] == r'\') {
      i += 2;
    } else if (text[i] == '"') {
      return i + 1;
    } else {
      i++;
    }
  }
  return text.length;
}
