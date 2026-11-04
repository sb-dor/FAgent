import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/build_mode.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'launch_config.freezed.dart';

/// {@template launch_config}
/// One Dart launch configuration of `.vscode/launch.json`, already split into what the app runs
/// with: the target, the flavor, the defines, the device and mode, and the flags left over.
/// {@endtemplate}
@freezed
abstract class LaunchConfig with _$LaunchConfig {
  /// {@macro launch_config}
  const factory LaunchConfig({
    /// The name the file gives the configuration; the menu shows it and the selection is stored
    /// by it.
    required String name,

    /// The `program`, relative to the project when it is inside it.
    @Default('lib/main.dart') String target,

    /// The `--flavor`; `null` for none.
    String? flavor,

    /// The `--dart-define`s, each `KEY=VALUE`.
    @Default(<String>[]) List<String> dartDefines,

    /// The remaining arguments, in the file's order, joined so `splitArgs` gives them back.
    @Default('') String extraArgs,

    /// The device the configuration runs on; `null` for the one picked in the app.
    String? deviceId,

    /// The build mode; `null` for the one picked in the app.
    BuildMode? mode,

    /// Variables added to the environment of `flutter run`.
    @Default(<String, String>{}) Map<String, String> environment,

    /// Why the configuration cannot run; `null` when it can.
    LaunchUnsupported? unsupported,

    /// Whether the file names a `preLaunchTask`, which the app skips.
    @Default(false) bool hasPreLaunchTask,
  }) = _LaunchConfig;
}

/// Why a [LaunchConfig] cannot run. The values are data, not text: the screen words them.
@immutable
sealed class LaunchUnsupported {
  const LaunchUnsupported();
}

/// The configuration uses a `${…}` variable other than `${workspaceFolder}`.
final class LaunchUnsupportedVariable extends LaunchUnsupported {
  /// Creates the reason.
  const LaunchUnsupportedVariable(this.name);

  /// The variable as the file spells it, for example `${env:HOME}`.
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LaunchUnsupportedVariable && other.name == name;

  @override
  int get hashCode => Object.hash(LaunchUnsupportedVariable, name);
}

/// The configuration's `cwd` is not the project folder.
final class LaunchCwdOutsideProject extends LaunchUnsupported {
  /// Creates the reason.
  const LaunchCwdOutsideProject(this.cwd);

  /// The `cwd` as the file spells it.
  final String cwd;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LaunchCwdOutsideProject && other.cwd == cwd;

  @override
  int get hashCode => Object.hash(LaunchCwdOutsideProject, cwd);
}

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
