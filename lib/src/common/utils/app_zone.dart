import 'dart:async';

import 'package:flutter_code_agent/src/common/telemetry/log_zone.dart';
import 'package:flutter_code_agent/src/common/utils/error_util.dart';
import 'package:l/l.dart';

/// Runs [fn] in the log zone: `print` goes to the log and an unhandled error goes to [ErrorUtil]
/// instead of vanishing. [logOptions] are replaced only by tests.
void appZone(Future<void> Function() fn, {LogOptions? logOptions}) => logZone(
  fn,
  onError: (error, stackTrace) =>
      unawaited(ErrorUtil.logError(error, stackTrace, hint: 'ROOT ERROR')),
  options:
      logOptions ??
      const LogOptions(
        messageFormatting: _messageFormatting,
        handlePrint: true,
        outputInRelease: false,
      ),
);

/// Formats the log message.
Object _messageFormatting(LogMessage log) => '${_timeFormat(log.timestamp)} | ${log.message}';

/// Formats the time.
String _timeFormat(DateTime time) => '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
