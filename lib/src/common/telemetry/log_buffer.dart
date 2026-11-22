import 'dart:collection';

import 'package:flutter_code_agent/src/common/telemetry/log_record.dart';
import 'package:l/l.dart';

/// A ring of the last log records in memory.
final class LogBuffer {
  /// How many records are kept.
  static const int limit = 10000;

  final Queue<LogMessage> _items = ListQueue<LogMessage>();

  /// The records from oldest to newest.
  Iterable<LogMessage> get logs => _items;

  /// Adds a record; on overflow the oldest one is dropped.
  void add(LogMessage message) {
    _items.addLast(message);
    while (_items.length > limit) {
      _items.removeFirst();
    }
  }

  /// Adds the records in order; if there are more than [limit], the newest stay.
  void addAll(Iterable<LogMessage> messages) {
    messages.forEach(add);
  }

  /// Removes all records.
  void clear() => _items.clear();

  /// The last [n] records in a form fit for sending to an isolate and [formatRawLogLines]:
  /// formatting and cleaning happen there, the main isolate does not compute them.
  List<RawLogLine> rawLines(int n) {
    final from = _items.length > n ? _items.length - n : 0;
    return [for (var i = from; i < _items.length; i++) rawLogLine(_items.elementAt(i))];
  }

  /// The last [n] log lines (`formatLogLine`), from oldest to newest.
  List<String> lastLines(int n) {
    final from = _items.length > n ? _items.length - n : 0;
    return [for (var i = from; i < _items.length; i++) formatLogLine(_items.elementAt(i))];
  }
}
