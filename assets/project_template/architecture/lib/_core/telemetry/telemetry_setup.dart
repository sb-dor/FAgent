// The error log runs on the VM only: the module (`logs.sqlite` in drift, `dart:io`, Sentry over
// `HttpClient`) does not compile for the web, so the app reaches it through this file alone, and on
// the web `ErrorUtil` writes to the console.
export 'package:{{package}}/_core/telemetry/telemetry_setup_io.dart'
    if (dart.library.js_interop) 'package:{{package}}/_core/telemetry/telemetry_setup_web.dart';
