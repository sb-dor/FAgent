import 'dart:async';

import 'package:flutter_code_agent/src/common/utils/error_util.dart';
import 'package:l/l.dart';

/// Catch all application errors and logs.
// ignore: experimental_member_use
void appZone(Future<void> Function() fn) => l.capture<void>(
  () => runZonedGuarded<void>(() => fn(), ErrorUtil.logError),
  const LogOptions(messageFormatting: _messageFormatting, handlePrint: true, outputInRelease: false),
);

/// Formats the log message.
Object _messageFormatting(LogMessage log) => '${_timeFormat(log.timestamp)} | ${log.message}';

/// Formats the time.
String _timeFormat(DateTime time) => '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
