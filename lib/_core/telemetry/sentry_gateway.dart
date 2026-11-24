import 'dart:async';
import 'dart:io';

import 'package:flutter_code_agent/_core/telemetry/crash_report_gateway.dart';
import 'package:flutter_code_agent/_core/telemetry/error_outbox.dart';
import 'package:meta/meta.dart';
import 'package:sentry/sentry.dart';

final RegExp _frame = RegExp(r'^#\d+\s+(.+?)\s+\((.+?):(\d+)(?::(\d+))?\)$');

/// The link of the app to Sentry on plain `sentry` (no `sentry_flutter`, no native part). An empty
/// DSN turns sending off: `reachable` and `send` give `false`, Sentry is not started.
///
/// Sentry starts once, at the first send (the sender sends only with the switch on and a DSN set),
/// and is closed by [close] when the user turns sending off. Flutter and isolate errors do not
/// get here by themselves: they go through `ErrorUtil`, the queue and secret cleaning.
final class SentryGateway implements ICrashReportGateway {
  /// Creates the gateway. [projectPackages] are the packages of the project: their frames are
  /// marked `inApp`. [probeUri] replaces the address of the connection check, [configureOptions]
  /// the Sentry options; both are only for tests.
  SentryGateway({
    required String dsn,
    required this.projectPackages,
    this.environment = 'production',
    this.release,
    this.timeout = const Duration(seconds: 5),
    @visibleForTesting this._probeUri,
    @visibleForTesting this._configureOptions,
  }) : dsn = dsn.trim();

  /// The DSN of the project in Sentry; empty turns sending off.
  final String dsn;

  /// The packages of the project: frames from them are `inApp`.
  final Set<String> projectPackages;

  /// The environment of the event.
  final String environment;

  /// The app version in the event.
  final String? release;

  /// How long to wait for the host when checking the connection (connect, request and answer
  /// together).
  final Duration timeout;

  final Uri? _probeUri;
  final void Function(SentryOptions options)? _configureOptions;
  Future<void>? _initialized;

  /// Whether a DSN is set.
  bool get enabled => dsn.isNotEmpty;

  @override
  Future<bool> reachable() async {
    if (!enabled) {
      return false;
    }
    final client = HttpClient();
    try {
      await _probe(client).timeout(timeout);
      // Any HTTP answer means the host is reachable.
      return true;
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  // The scheme and the port come from the DSN: `http://…:9000/…` is probed over http on port 9000.
  Future<void> _probe(HttpClient client) async {
    final dsnUri = Uri.parse(dsn);
    final uri =
        _probeUri ??
        Uri(
          scheme: dsnUri.scheme,
          host: dsnUri.host,
          port: dsnUri.hasPort ? dsnUri.port : null,
          path: '/',
        );
    final request = await client.openUrl('HEAD', uri);
    final response = await request.close();
    await response.drain<void>();
  }

  /// Starts Sentry if it is not started yet. Does nothing without a DSN.
  Future<void> start() async {
    if (!enabled) {
      return;
    }
    try {
      await (_initialized ??= _init());
    } on Object {
      // An invalid DSN must not count as Sentry refusing: the entry stays in the queue.
      _initialized = null;
      rethrow;
    }
  }

  @override
  Future<bool> send(OutboxEntry entry) async {
    if (!enabled) {
      return false;
    }
    await start();
    final stackTrace = _stackTrace(entry.stack);
    final event = SentryEvent(
      timestamp: entry.firstAt,
      level: switch (entry.level) {
        'fatal' => SentryLevel.fatal,
        'warning' => SentryLevel.warning,
        _ => SentryLevel.error,
      },
      exceptions: [SentryException(type: entry.type, value: entry.message, stackTrace: stackTrace)],
      fingerprint: [entry.fingerprint],
      tags: {'platform': entry.platform, 'app_version': entry.appVersion},
      // ignore: deprecated_member_use
      extra: {
        'count': entry.count,
        'lastAt': entry.lastAt.toIso8601String(),
        'hint': ?entry.hint,
        // A stack that did not parse into frames (obfuscated) goes as it is.
        if (stackTrace.frames.isEmpty) 'stack': entry.stack,
      },
      breadcrumbs: [for (final line in entry.breadcrumbs) _breadcrumb(line)],
    );
    final id = await Sentry.captureEvent(event);
    return id.toString() != const SentryId.empty().toString();
  }

  /// Closes Sentry; if it is still starting, waits for the start to finish. The next send starts
  /// it again.
  Future<void> close() async {
    final starting = _initialized;
    if (starting == null) {
      return;
    }
    _initialized = null;
    try {
      await starting;
    } on Object {
      // The start failed: nothing to close.
      return;
    }
    await Sentry.close();
  }

  Future<void> _init() async {
    await Sentry.init((options) {
      options
        ..dsn = dsn
        ..environment = environment
        ..release = release
        ..debug = false
        ..sendDefaultPii = false
        ..enableDeduplication = false
        ..enablePrintBreadcrumbs = false;
      // Unhandled isolate errors go to the log and the queue through ErrorUtil, not around them.
      options.integrations.whereType<IsolateErrorIntegration>().toList().forEach(
        options.removeIntegration,
      );
      _configureOptions?.call(options);
      // Our own event cleaning runs before a foreign (test) `beforeSend`.
      final next = options.beforeSend;
      options.beforeSend = (event, hint) {
        _dropPaths(event);
        return next == null ? event : next(event, hint);
      };
    });
  }

  // The SDK itself adds the OS, the Dart version, the language and the time zone, the processor
  // count and the memory to the contexts; the path to `package_config.json` holds the user name
  // and the project directory, so it is not sent.
  void _dropPaths(SentryEvent event) {
    final dart = event.contexts['dart_context'];
    if (dart is Map) {
      dart.remove('package_config');
    }
  }

  // Frames in Sentry's order: from the oldest call to the newest. Lines that do not look like a
  // Dart frame (`#0  Class.method (package:app/file.dart:10:5)`) are skipped.
  SentryStackTrace _stackTrace(String stack) {
    final frames = <SentryStackFrame>[];
    for (final line in stack.split('\n')) {
      final m = _frame.firstMatch(line.trim());
      if (m == null) continue;
      final path = m.group(2)!;
      frames.add(
        SentryStackFrame(
          function: m.group(1),
          absPath: path,
          fileName: path.split('/').last,
          lineNo: int.parse(m.group(3)!),
          colNo: int.tryParse(m.group(4) ?? ''),
          inApp: _isProjectFrame(path),
        ),
      );
    }
    return SentryStackTrace(frames: frames.reversed.toList());
  }

  bool _isProjectFrame(String path) {
    if (!path.startsWith('package:')) {
      return false;
    }
    final name = path.substring('package:'.length).split('/').first;
    return projectPackages.contains(name);
  }

  // A log line `2026-11-12T10:15:03.120Z [E] text`.
  Breadcrumb _breadcrumb(String line) {
    final time = DateTime.tryParse(line.split(' ').first);
    return Breadcrumb(message: line, timestamp: time?.toUtc());
  }
}
