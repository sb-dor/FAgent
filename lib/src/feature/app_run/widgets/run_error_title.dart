import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error_kind.dart';

/// The title of [error] in the language of [lcl]; an error of kind [RunErrorKind.other] keeps the
/// title the app or the framework printed.
String runErrorTitle(GeneratedLocalization lcl, RunError error) => switch (error.kind) {
  RunErrorKind.projectNotFound => lcl.runErrorProjectNotFound,
  RunErrorKind.flutterNotFound => lcl.runErrorFlutterNotFound,
  RunErrorKind.buildFailed => lcl.runErrorBuildFailed,
  RunErrorKind.appExited => lcl.runErrorAppExited,
  RunErrorKind.compilation => lcl.runErrorCompilation,
  RunErrorKind.unhandledException => lcl.runErrorUnhandledException,
  RunErrorKind.layoutOverflow => lcl.runErrorLayoutOverflow,
  RunErrorKind.exception => lcl.runErrorException,
  RunErrorKind.devToolsFailed => lcl.runErrorDevToolsFailed,
  RunErrorKind.hotReloadFailed => lcl.runErrorHotReloadFailed,
  RunErrorKind.hotRestartFailed => lcl.runErrorHotRestartFailed,
  RunErrorKind.screenshotFailed => lcl.runErrorScreenshotFailed,
  RunErrorKind.other => error.title,
};
