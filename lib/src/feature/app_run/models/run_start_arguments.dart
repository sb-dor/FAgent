import 'package:flutter_code_agent/src/feature/app_run/data/launch_config_reader.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/launch_config.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'run_start_arguments.freezed.dart';

/// {@template run_start_arguments}
/// What one start passes to `flutter run` besides the device and the mode: the entry point, the
/// arguments and the variables added to the environment.
/// {@endtemplate}
@freezed
abstract class RunStartArguments with _$RunStartArguments {
  /// {@macro run_start_arguments}
  const factory RunStartArguments({
    /// The entry point (`-t`).
    @Default('lib/main.dart') String target,

    /// The flavor, the defines and the other flags.
    @Default(RunArguments()) RunArguments arguments,

    /// Variables added to the environment of `flutter run`, over the app's own.
    @Default(<String, String>{}) Map<String, String> environment,
  }) = _RunStartArguments;

  /// The start of [config]: its target, flavor, defines, other flags and `env`, as the file gives
  /// them (a relative `--dart-define-from-file` path stays relative: `flutter run` runs in the
  /// project folder). The project's Default arguments are not part of it.
  factory RunStartArguments.fromLaunchConfig(LaunchConfig config) => RunStartArguments(
    target: config.target,
    arguments: RunArguments(
      flavor: config.flavor,
      dartDefines: config.dartDefines,
      extraArgs: config.extraArgs,
    ),
    environment: config.environment,
  );
}

/// The selected launch configuration [name] cannot start: the configuration is [unsupported], or
/// the `launch.json` it comes from is [unreadable]. Exactly one of the two is set.
final class RunConfigNotStartable implements Exception {
  /// The configuration uses what the app cannot run.
  const RunConfigNotStartable.unsupported(this.name, LaunchUnsupported this.unsupported)
    : unreadable = null;

  /// The `launch.json` cannot be read, so the configuration is not known.
  const RunConfigNotStartable.unreadable(this.name, LaunchConfigsUnreadable this.unreadable)
    : unsupported = null;

  /// The name of the configuration.
  final String name;

  /// Why the configuration cannot run.
  final LaunchUnsupported? unsupported;

  /// What is wrong with the file.
  final LaunchConfigsUnreadable? unreadable;

  @override
  String toString() => switch ((unsupported, unreadable)) {
    (LaunchUnsupportedVariable(:final name), _) =>
      'RunConfigNotStartable: "${this.name}" uses $name',
    (LaunchCwdOutsideProject(:final cwd), _) =>
      'RunConfigNotStartable: "$name" runs in $cwd, outside the project',
    (_, final file?) =>
      'RunConfigNotStartable: launch.json cannot be read (${file.kind.name}'
          '${file.detail == null ? '' : ': ${file.detail}'})',
    _ => 'RunConfigNotStartable: "$name"',
  };
}
