/// The error log, the error queue and secret cleaning: the telemetry module of every app of this
/// repository. An app's glue (`lib/_core/telemetry/`) imports it; code that also compiles for the
/// web imports `portable.dart` instead.
library;

export 'package:telemetry/src/telemetry.dart';
