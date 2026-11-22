/// The part of the telemetry module that compiles on every platform, the web included: the log
/// zone and secret cleaning. The rest (`telemetry.dart`) needs `dart:io`, drift and SQLite.
library;

export 'package:telemetry/src/clip.dart';
export 'package:telemetry/src/log_zone.dart';
export 'package:telemetry/src/redact.dart';
