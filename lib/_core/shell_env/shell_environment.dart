import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:l/l.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// {@template shell_environment}
/// Environment variables of the user's interactive login shell.
///
/// macOS GUI apps do not inherit the shell `PATH`, so tools installed through
/// Homebrew, nvm and the like are invisible to `Process.start` without it.
/// Every child process (agents, `flutter`, `git`) is started with [variables].
/// {@endtemplate}
@immutable
final class ShellEnvironment {
  /// {@macro shell_environment}
  const ShellEnvironment(this.variables, {this.isFallback = false});

  /// Resolved environment variables.
  final Map<String, String> variables;

  /// `true` when the shell could not be queried and [variables] are the app's
  /// own environment plus well-known tool directories.
  final bool isFallback;

  static const String _startMarker = '__FLUTTER_CODE_AGENT_ENV_START__';
  static const String _endMarker = '__FLUTTER_CODE_AGENT_ENV_END__';

  /// Directories appended to `PATH` in the fallback environment.
  @visibleForTesting
  static const List<String> fallbackDirectories = <String>['/opt/homebrew/bin', '/usr/local/bin'];

  /// Queries [shell] (default `$SHELL`, then `/bin/zsh`) as an interactive login
  /// shell (`-ilc`: nvm and similar tools are set up in `.zshrc`, not `.zprofile`).
  ///
  /// Falls back to the current process environment when the shell fails or does
  /// not answer within [timeout].
  static Future<ShellEnvironment> resolve({
    String? shell,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final current = io.Platform.environment;
    final executable = shell ?? current['SHELL'] ?? '/bin/zsh';
    try {
      final process = await io.Process.start(executable, <String>[
        '-ilc',
        "printf '%s' '$_startMarker'; env -0; printf '%s' '$_endMarker'",
      ]);
      // Interactive shells may wait for input; give them EOF right away.
      process.stdin.close().ignore();
      final stdout = process.stdout.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      process.stderr.drain<void>().ignore();
      final exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill(io.ProcessSignal.sigkill);
          throw TimeoutException('$executable -ilc did not finish', timeout);
        },
      );
      final variables = parseEnvOutput(utf8.decode(await stdout, allowMalformed: true));
      if (variables == null || !variables.containsKey('PATH')) {
        throw StateError('$executable -ilc exited with $exitCode without an environment');
      }
      return ShellEnvironment(Map<String, String>.unmodifiable(variables));
    } on Object catch (error, stackTrace) {
      l.w('Shell environment | falling back to the app environment: $error', stackTrace);
      return fallback(current);
    }
  }

  /// The [current] environment with [fallbackDirectories] appended to `PATH`.
  @visibleForTesting
  static ShellEnvironment fallback(Map<String, String> current) {
    final path = <String>[...?current['PATH']?.split(':').where((dir) => dir.isNotEmpty)];
    for (final dir in fallbackDirectories) {
      if (!path.contains(dir)) path.add(dir);
    }
    return ShellEnvironment(
      Map<String, String>.unmodifiable(<String, String>{...current, 'PATH': path.join(':')}),
      isFallback: true,
    );
  }

  /// Parses `env -0` output wrapped in the markers, ignoring anything the rc
  /// files printed around it. Returns `null` when the markers are missing.
  @visibleForTesting
  static Map<String, String>? parseEnvOutput(String output) {
    final start = output.indexOf(_startMarker);
    final end = output.lastIndexOf(_endMarker);
    if (start < 0 || end < start) return null;
    final body = output.substring(start + _startMarker.length, end);
    final variables = <String, String>{};
    for (final entry in body.split('\u0000')) {
      final separator = entry.indexOf('=');
      if (separator <= 0) continue;
      variables[entry.substring(0, separator)] = entry.substring(separator + 1);
    }
    return variables;
  }

  /// Absolute path of [name] found on `PATH`, or `null`.
  String? which(String name) {
    for (final dir in (variables['PATH'] ?? '').split(':')) {
      if (dir.isEmpty) continue;
      final candidate = p.join(dir, name);
      if (io.FileSystemEntity.isFileSync(candidate)) return candidate;
    }
    return null;
  }

  @override
  String toString() => 'ShellEnvironment(${variables.length} variables, fallback: $isFallback)';
}
