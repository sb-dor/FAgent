import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_code_agent/_core/telemetry/crash_report_gateway.dart';
import 'package:flutter_code_agent/_core/telemetry/error_outbox.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry_status.dart';
import 'package:l/l.dart';

/// Sender of the error queue: at start and then every [every], one entry at a time, up to
/// [perPass] per pass.
/// Throws nothing outward and does not call `ErrorUtil`.
final class TelemetrySender {
  TelemetrySender({
    required this.outbox,
    required this.gateway,
    required this.enabled,
    this.every = const Duration(minutes: 5),
    this.perPass = 50,
    this.maxAttempts = 3,
  }) {
    _onChanged = () => _track(refreshQueued());
    outbox.onChanged = _onChanged;
  }

  late final void Function() _onChanged;
  final Set<Future<void>> _refreshes = {};

  void _track(Future<void> refresh) {
    _refreshes.add(refresh);
    unawaited(refresh.whenComplete(() => _refreshes.remove(refresh)));
  }

  /// Waits for the started queue counter refreshes: before the log database is closed.
  Future<void> settled() async {
    while (_refreshes.isNotEmpty) {
      await Future.wait(_refreshes.toList());
    }
  }

  final ErrorOutbox outbox;
  final ICrashReportGateway gateway;

  /// Whether sending is on (the user's setting); checked on every pass.
  final bool Function() enabled;

  /// The period of passes.
  final Duration every;

  /// How many entries one pass takes.
  final int perPass;

  /// After how many rejected attempts, with the service reachable, an entry is removed.
  final int maxAttempts;

  final StreamController<TelemetryStatus> _status = StreamController<TelemetryStatus>.broadcast();
  TelemetryStatus _current = TelemetryStatus.initial;
  Timer? _timer;
  bool _running = false;
  bool _stopRequested = false;
  // The last pass of `perPass` entries had none accepted while the service was reachable: old bad
  // entries block the queue, the next pass takes the newest.
  bool _newestFirst = false;
  Future<void>? _pass;

  /// State changes.
  Stream<TelemetryStatus> get status => _status.stream;

  /// The current state.
  TelemetryStatus get current => _current;

  /// The first pass at once, then every [every].
  void start() {
    _stopRequested = false;
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => unawaited(runPass()));
    unawaited(runPass());
  }

  /// Stops the timer, interrupts a running pass after the current entry and waits for its end.
  Future<void> stop() async {
    _stopRequested = true;
    _timer?.cancel();
    _timer = null;
    await _pass;
  }

  /// Stops the sender and closes the [status] stream.
  Future<void> dispose() async {
    await stop();
    // Drop the subscription only if the queue is still ours.
    if (outbox.onChanged == _onChanged) {
      outbox.onChanged = null;
    }
    await _status.close();
  }

  /// Refreshes [TelemetryStatus.queued] from the queue (one COUNT).
  Future<void> refreshQueued() async {
    try {
      _emit(queued: await outbox.length());
    } on Object catch (error) {
      _report('Error sender: failed to read the queue: $error');
    }
  }

  /// One pass. If the previous one is still running, returns at once.
  Future<void> runPass() {
    if (_running) {
      return Future<void>.value();
    }
    return _pass = _runPass();
  }

  Future<void> _runPass() async {
    _running = true;
    // A manual pass after stop() works: the flag belongs to the pass that was running.
    _stopRequested = false;
    try {
      if (!enabled()) {
        return;
      }
      _emit(sending: true);
      await refreshQueued();
      final ok = await gateway.reachable();
      _emit(lastCheckAt: clock.now().toUtc(), reachable: ok);
      if (!ok) {
        return;
      }
      // The pass does not stop at a rejected entry: the service may accept only part (429, a
      // dropped connection). A rejected entry gets an attempt only if something after it in the
      // same pass is accepted: then the service is healthy and the entry is bad. The rejected
      // tail gets no attempts.
      final rejected = <OutboxEntry>[];
      final batch = await outbox.sendable(perPass, newestFirst: _newestFirst);
      var acceptedCount = 0;
      var completed = true;
      for (final entry in batch) {
        if (_stopRequested || !enabled()) {
          completed = false;
          break;
        }
        // Consent may have moved later while this pass runs: an entry from before it stays.
        final since = outbox.consentSince;
        if (since != null && entry.firstAt.isBefore(since)) {
          continue;
        }
        // The same goes for its breadcrumbs.
        if (await _send(outbox.consented(entry))) {
          acceptedCount++;
          for (final bad in rejected) {
            await _penalize(bad);
          }
          rejected.clear();
          _emit(lastSentAt: clock.now().toUtc());
        } else {
          rejected.add(entry);
        }
      }
      if (completed) {
        _newestFirst = !_newestFirst && batch.length >= perPass && acceptedCount == 0;
      }
    } on Object catch (error) {
      _report('Error sender: the pass failed: $error');
    } finally {
      _running = false;
      await _finish();
    }
  }

  /// Whether the service accepted the entry. An accepted entry is removed from the queue. A
  /// `count` increase while this entry was being sent may be lost: acceptable.
  Future<bool> _send(OutboxEntry entry) async {
    final bool accepted;
    try {
      accepted = await gateway.send(entry);
    } on Object {
      return false;
    }
    if (accepted) {
      await outbox.remove(entry.id);
    }
    return accepted;
  }

  Future<void> _penalize(OutboxEntry entry) async {
    if (entry.attempts + 1 >= maxAttempts) {
      await outbox.remove(entry.id);
      l.w('report rejected by the service: ${entry.type}, $maxAttempts attempts');
    } else {
      await outbox.markAttempt(entry.id);
    }
  }

  Future<void> _finish() async {
    var queued = _current.queued;
    try {
      queued = await outbox.length();
    } on Object catch (error) {
      _report('Error sender: failed to read the queue: $error');
    }
    _emit(sending: false, queued: queued);
  }

  void _emit({
    bool? sending,
    int? queued,
    DateTime? lastSentAt,
    DateTime? lastCheckAt,
    bool? reachable,
  }) {
    _current = TelemetryStatus(
      queued: queued ?? _current.queued,
      sending: sending ?? _current.sending,
      lastSentAt: lastSentAt ?? _current.lastSentAt,
      lastCheckAt: lastCheckAt ?? _current.lastCheckAt,
      reachable: reachable ?? _current.reachable,
    );
    if (!_status.isClosed) {
      _status.add(_current);
    }
  }

  void _report(String text) {
    try {
      stderr.writeln(text);
    } on Object {
      // stderr is unavailable: nothing to lose.
    }
  }
}
