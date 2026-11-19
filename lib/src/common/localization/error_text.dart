import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_exceptions.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/feature/projects/data/projects_repository.dart';
import 'package:flutter_code_agent/src/feature/sessions/data/sessions_repository.dart';

/// Turns any error the app can meet into a localized sentence.
///
/// Cases go from specific to general. An unknown error is its `toString()` in debug builds, to see
/// what was missed ([debug]), and a generic sentence otherwise.
String errorText(GeneratedLocalization lcl, Object? error, {bool debug = kDebugMode}) =>
    switch (error) {
      FileSystemException(:final String path, :final message, :final osError)
          when path.isNotEmpty =>
        lcl.errorFile(path, osError?.message ?? message),
      FileSystemException(:final message, :final osError) => osError?.message ?? message,
      ProcessException(:final executable) => lcl.errorProcess(executable),
      TimeoutException() => lcl.errorTimeout,
      FlutterNotFoundException() => lcl.errorFlutterNotFound,
      ChatBusyException() => lcl.errorChatBusy,
      ProjectBusyException() => lcl.errorProjectBusy,
      _ => debug ? '$error' : lcl.errorUnknown,
    };
