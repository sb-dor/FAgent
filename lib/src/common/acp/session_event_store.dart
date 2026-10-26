import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:l/l.dart';

/// {@template session_event_store}
/// The single writer and in-memory view of one chat's journal.
///
/// * `seq` is assigned synchronously when an event is added.
/// * Agent frames ([addAgentFrame]) are visible at once and written in
///   batches every [flushInterval].
/// * Durable events ([addDurable]) first write everything queued before them,
///   in the same transaction, and become visible only after the commit. If the
///   write fails they throw and are never shown.
/// * Writes run one after another, strictly in `seq` order.
/// {@endtemplate}
final class SessionEventStore {
  SessionEventStore._(
    this._database,
    this.sessionId,
    this._events,
    this._nextSeq,
    this.flushInterval,
  );

  /// Loads the journal of [sessionId] and returns a store that appends to it.
  static Future<SessionEventStore> open(
    AppDatabase database,
    int sessionId, {
    Duration flushInterval = const Duration(milliseconds: 200),
  }) async {
    final rows =
        await (database.select(database.sessionEventsTable)
              ..where((e) => e.sessionId.equals(sessionId))
              ..orderBy(<OrderClauseGenerator<$SessionEventsTableTable>>[
                (e) => OrderingTerm.asc(e.seq),
              ]))
            .get();
    final events = <SessionEvent>[for (final row in rows) _fromRow(row)];
    return SessionEventStore._(
      database,
      sessionId,
      events,
      events.isEmpty ? 0 : events.last.seq + 1,
      flushInterval,
    );
  }

  static SessionEvent _fromRow(SessionEventRow row) => SessionEvent(
    seq: row.seq,
    origin: SessionEventOrigin.values.byName(row.origin),
    kind: row.kind,
    payload: (jsonDecode(row.payload) as Map<Object?, Object?>).cast<String, Object?>(),
    createdAt: row.createdAt,
  );

  final AppDatabase _database;

  /// `sessions.id` of the chat.
  final int sessionId;

  /// How long agent frames wait before they are written.
  final Duration flushInterval;

  final List<SessionEvent> _events;
  final List<SessionEvent> _pending = <SessionEvent>[];
  final StreamController<SessionEvent> _added = StreamController<SessionEvent>.broadcast(
    sync: true,
  );
  Future<void> _writes = Future<void>.value();
  Timer? _flushTimer;
  int _nextSeq;
  bool _closed = false;

  /// Whether [close] was called; adding events then throws.
  bool get isClosed => _closed;

  /// Visible events in `seq` order.
  List<SessionEvent> get events => List<SessionEvent>.unmodifiable(_events);

  /// Every event as it becomes visible. Durable events may arrive after agent
  /// frames with a higher `seq`; consumers order by `seq`.
  Stream<SessionEvent> get added => _added.stream;

  /// Adds a raw agent frame: visible now, written with the next batch.
  SessionEvent addAgentFrame(String kind, Map<String, Object?> payload) {
    _checkOpen();
    final event = _create(SessionEventOrigin.agent, kind, payload);
    _pending.add(event);
    _show(event);
    _flushTimer ??= Timer(flushInterval, () => unawaited(flush()));
    return event;
  }

  /// Adds an event that must be on disk before anything acts on it.
  ///
  /// Everything queued earlier is written in the same transaction. Throws when
  /// the write fails; the event is then not shown.
  Future<SessionEvent> addDurable(
    SessionEventOrigin origin,
    String kind,
    Map<String, Object?> payload,
  ) async {
    _checkOpen();
    final event = _create(origin, kind, payload);
    _pending.add(event);
    await _write(durable: event);
    _show(event);
    return event;
  }

  /// Writes all queued frames.
  Future<void> flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    return _pending.isEmpty ? _writes : _write();
  }

  /// Writes what is queued and stops accepting events.
  Future<void> close() async {
    if (_closed) return;
    try {
      await flush();
    } on Object catch (error, stackTrace) {
      l.w(
        'SessionEventStore | session $sessionId lost unsaved events on close: $error',
        stackTrace,
      );
    } finally {
      _closed = true;
      await _added.close();
    }
  }

  SessionEvent _create(SessionEventOrigin origin, String kind, Map<String, Object?> payload) =>
      SessionEvent(
        seq: _nextSeq++,
        origin: origin,
        kind: kind,
        payload: payload,
        createdAt: DateTime.now(),
      );

  void _show(SessionEvent event) {
    final index = _events.lastIndexWhere((e) => e.seq < event.seq) + 1;
    _events.insert(index, event);
    if (!_added.isClosed) _added.add(event);
  }

  /// Chains one transaction writing everything pending right now.
  ///
  /// On failure the already visible agent frames go back to the queue for the
  /// next attempt; the [durable] event that triggered the write does not (it
  /// was never shown and its caller gets the error).
  Future<void> _write({SessionEvent? durable}) {
    var batch = const <SessionEvent>[];
    // The batch is taken when the write runs, not when it is queued: frames a
    // failed earlier write put back are then written before [durable].
    final write = _writes.then((_) {
      batch = List<SessionEvent>.of(_pending)..sort((a, b) => a.seq.compareTo(b.seq));
      _pending.clear();
      if (batch.isEmpty) return Future<void>.value();
      return _database.batch((b) {
        b.insertAll(_database.sessionEventsTable, <SessionEventsTableCompanion>[
          for (final event in batch)
            SessionEventsTableCompanion.insert(
              sessionId: sessionId,
              seq: event.seq,
              origin: event.origin.name,
              kind: event.kind,
              payload: jsonEncode(event.payload),
              createdAt: Value<DateTime>(event.createdAt),
            ),
        ]);
      });
    });
    // A failed write must not block later ones; the caller of this write sees
    // the error.
    _writes = write.catchError((Object error, StackTrace stackTrace) {
      l.w(
        'SessionEventStore | session $sessionId failed to write ${batch.length} events: $error',
        stackTrace,
      );
      _pending.insertAll(0, batch.where((e) => !identical(e, durable)));
    });
    return write;
  }

  void _checkOpen() {
    if (_closed) throw StateError('SessionEventStore for session $sessionId is closed');
  }
}
