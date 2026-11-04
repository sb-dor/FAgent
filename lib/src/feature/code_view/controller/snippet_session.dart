import 'package:flutter_code_agent/src/feature/code_view/models/snippet.dart';
import 'package:re_editor/re_editor.dart';

/// {@template snippet_session}
/// A snippet just inserted into [CodeLineEditingController]: Tab and ⇧Tab move between its stops,
/// typing in a stop copies the text to its mirrors, and the session ends at `$0`, on [end], or when
/// the caret leaves the snippet.
///
/// Offsets are kept in the text joined with `\n` (what columns count), whatever the file's line
/// break.
/// {@endtemplate}
final class SnippetSession {
  /// {@macro snippet_session}
  ///
  /// [snippet] was inserted at [line] and [column]; the first stop is selected.
  SnippetSession(
    this._editing, {
    required int line,
    required int column,
    required Snippet snippet,
  }) {
    _text = _current();
    final base = _offsetOf(_text, line, column);
    _span = (base, base + snippet.text.length);
    _stops = <_Stop>[
      for (final stop in snippet.stops)
        _Stop(stop.index, <(int, int)>[
          for (final (start, end) in stop.offsets) (base + start, base + end),
        ]),
    ];
    _select(0);
  }

  final CodeLineEditingController _editing;
  late List<_Stop> _stops;

  /// The whole inserted snippet.
  late (int, int) _span;

  /// The text the offsets are about.
  late String _text;

  int _active = 0;
  bool _ended = false;

  /// The session's own mirror edits are not the user's.
  bool _mirroring = false;

  /// Whether Tab still moves between stops.
  bool get active => !_ended;

  String _current() => _editing.codeLines.asString(TextLineBreak.lf);

  static int _offsetOf(String text, int line, int column) {
    var offset = 0;
    for (var i = 0; i < line; i++) {
      final next = text.indexOf('\n', offset);
      if (next < 0) return text.length;
      offset = next + 1;
    }
    return offset + column;
  }

  static (int, int) _positionOf(String text, int offset) {
    final before = text.substring(0, offset.clamp(0, text.length));
    final line = '\n'.allMatches(before).length;
    return (line, offset - (before.lastIndexOf('\n') + 1));
  }

  CodeLineSelection _selectionOf((int, int) range) {
    final (startLine, startColumn) = _positionOf(_text, range.$1);
    final (endLine, endColumn) = _positionOf(_text, range.$2);
    return CodeLineSelection(
      baseIndex: startLine,
      baseOffset: startColumn,
      extentIndex: endLine,
      extentOffset: endColumn,
    );
  }

  /// Selects stop [index]; `$0` puts the caret there and ends the session.
  void _select(int index) {
    _active = index;
    final stop = _stops[index];
    _mirroring = true;
    try {
      _editing.selection = _selectionOf(stop.ranges.first);
    } finally {
      _mirroring = false;
    }
    if (stop.index == 0) _ended = true;
  }

  /// Selects the next stop; `false` when the session is over.
  bool next() {
    if (_ended) return false;
    if (_active + 1 >= _stops.length) {
      _ended = true;
      return false;
    }
    _select(_active + 1);
    return true;
  }

  /// Selects the previous stop; `false` at the first one or when the session is over.
  bool previous() {
    if (_ended || _active == 0) return false;
    _select(_active - 1);
    return true;
  }

  /// Ends the session.
  void end() => _ended = true;

  /// The editor changed: offsets follow the edit, an edit inside a stop is copied to its mirrors,
  /// and a caret outside the snippet ends the session.
  void onEdit() {
    if (_ended || _mirroring) return;
    final now = _current();
    if (now != _text) {
      if (!_follow(_text, now)) {
        _ended = true;
        return;
      }
    }
    final caret = _offsetOf(_text, _editing.selection.extentIndex, _editing.selection.extentOffset);
    if (caret < _span.$1 || caret > _span.$2) _ended = true;
  }

  /// Moves the offsets from [before] to [after]; `false` when the edit runs across a stop.
  bool _follow(String before, String after) {
    var prefix = 0;
    final shortest = before.length < after.length ? before.length : after.length;
    while (prefix < shortest && before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shortest - prefix &&
        before.codeUnitAt(before.length - 1 - suffix) ==
            after.codeUnitAt(after.length - 1 - suffix)) {
      suffix++;
    }
    final oldEnd = before.length - suffix;
    final delta = after.length - before.length;
    _text = after;

    // The stop range the edit lies in grows or shrinks; everything after it moves.
    (int stop, int range)? edited;
    for (var s = 0; s < _stops.length && edited == null; s++) {
      for (var r = 0; r < _stops[s].ranges.length; r++) {
        final (start, end) = _stops[s].ranges[r];
        if (start <= prefix && oldEnd <= end) {
          edited = (s, r);
          break;
        }
      }
    }
    (int, int) move((int, int) range, {required bool grows}) {
      final (start, end) = range;
      if (grows) return (start, end + delta);
      if (end <= prefix) return range;
      if (start >= oldEnd) return (start + delta, end + delta);
      return (-1, -1);
    }

    for (var s = 0; s < _stops.length; s++) {
      final ranges = _stops[s].ranges;
      for (var r = 0; r < ranges.length; r++) {
        final moved = move(ranges[r], grows: edited == (s, r));
        if (moved.$1 < 0) return false;
        ranges[r] = moved;
      }
    }
    final (spanStart, spanEnd) = _span;
    if (prefix < spanStart && oldEnd > spanStart) return false;
    _span = (spanStart, spanEnd + (spanStart <= prefix && oldEnd <= spanEnd ? delta : 0));
    if (spanStart > prefix && spanStart >= oldEnd) _span = (spanStart + delta, spanEnd + delta);

    if (edited != null) _mirror(edited.$1, edited.$2);
    return true;
  }

  /// Copies the text of range [source] of stop [stop] to the stop's other ranges.
  void _mirror(int stop, int source) {
    final ranges = _stops[stop].ranges;
    final (start, end) = ranges[source];
    final value = _text.substring(start, end);
    var caret = _offsetOf(_text, _editing.selection.extentIndex, _editing.selection.extentOffset);
    _mirroring = true;
    try {
      // From the last range back, so a replacement does not move the ranges still to do.
      final order = <int>[for (var r = 0; r < ranges.length; r++) r]
        ..sort((a, b) => ranges[b].$1.compareTo(ranges[a].$1));
      for (final r in order) {
        if (r == source) continue;
        final (from, to) = ranges[r];
        if (_text.substring(from, to) == value) continue;
        _editing.selection = _selectionOf(ranges[r]);
        _editing.replaceSelection(value);
        _text = _current();
        final delta = value.length - (to - from);
        for (final other in _stops) {
          for (var i = 0; i < other.ranges.length; i++) {
            final (s, e) = other.ranges[i];
            if (identical(other.ranges, ranges) && i == r) {
              other.ranges[i] = (from, from + value.length);
            } else if (s >= to) {
              other.ranges[i] = (s + delta, e + delta);
            }
          }
        }
        if (caret >= to) caret += delta;
        _span = (_span.$1, _span.$2 + delta);
      }
      final (line, column) = _positionOf(_text, caret);
      _editing.selection = CodeLineSelection.collapsed(index: line, offset: column);
    } finally {
      _mirroring = false;
    }
  }
}

final class _Stop {
  _Stop(this.index, this.ranges);

  final int index;
  final List<(int, int)> ranges;
}
