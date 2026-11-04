import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/launch_config.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_start_arguments.dart';

/// The words for what the launch configurations model says as data: why a configuration cannot
/// run, why `launch.json` cannot be read, and why a start was refused.
extension LaunchConfigTexts on GeneratedLocalization {
  /// "Unsupported: ${env:HOME}" for the reason [reason].
  String launchUnsupportedText(LaunchUnsupported reason) => switch (reason) {
    LaunchUnsupportedVariable(:final name) => launchUnsupportedVariable(name),
    LaunchCwdOutsideProject(:final cwd) => launchUnsupportedCwd(cwd),
  };

  /// `launch.json can't be read: invalid JSON: ...` with the parser's message, for [file].
  String launchUnreadableText(LaunchConfigsUnreadable file) {
    final reason = switch (file.kind) {
      LaunchUnreadableKind.invalidJson => launchReasonInvalidJson,
      LaunchUnreadableKind.notAnObject => launchReasonNotObject,
      LaunchUnreadableKind.noConfigurationsList => launchReasonNoConfigurations,
      LaunchUnreadableKind.cannotRead => launchReasonCannotRead,
    };
    final detail = file.detail;
    return launchUnreadable(detail == null || detail.isEmpty ? reason : '$reason: $detail');
  }

  /// `“Name” can't run. ...` with the reason, for a start the app refused.
  String runRefusedText(RunConfigNotStartable refusal) {
    final why = switch ((refusal.unsupported, refusal.unreadable)) {
      (final LaunchUnsupported reason, _) => launchUnsupportedText(reason),
      (_, final LaunchConfigsUnreadable file) => launchUnreadableText(file),
      _ => '',
    };
    return runConfigCannotStart(refusal.name, why);
  }
}
