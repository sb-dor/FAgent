import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// {@template bounded_line_splitter}
/// Splits a byte stream into lines without unbounded buffering.
///
/// A line longer than [maxLineBytes] is cut at the limit: the rest is dropped
/// while it arrives (never accumulated) and the emitted line ends with `…`.
/// ANSI escape sequences are removed. Use it for diagnostic output only
/// (stderr, login output) — never for protocol streams.
/// {@endtemplate}
final class BoundedLineSplitter extends StreamTransformerBase<List<int>, String> {
  /// {@macro bounded_line_splitter}
  const BoundedLineSplitter({this.maxLineBytes = 2000});

  /// Maximum number of bytes kept per line.
  final int maxLineBytes;

  static final RegExp _ansi = RegExp(r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*\x07|[@-Z\\-_])');

  /// Removes ANSI escape sequences from [line].
  static String stripAnsi(String line) => line.replaceAll(_ansi, '');

  @override
  Stream<String> bind(Stream<List<int>> stream) =>
      Stream<String>.eventTransformed(stream, (sink) => _BoundedLineSink(sink, maxLineBytes));
}

final class _BoundedLineSink implements EventSink<List<int>> {
  _BoundedLineSink(this._out, this._maxLineBytes) : _buffer = Uint8List(_maxLineBytes);

  final EventSink<String> _out;
  final int _maxLineBytes;
  final Uint8List _buffer;
  int _length = 0;
  bool _truncated = false;

  @override
  void add(List<int> chunk) {
    for (final byte in chunk) {
      if (byte == 0x0A) {
        _emit();
      } else if (_length < _maxLineBytes) {
        _buffer[_length++] = byte;
      } else {
        _truncated = true;
      }
    }
  }

  void _emit() {
    var end = _length;
    if (end > 0 && _buffer[end - 1] == 0x0D) end--;
    final text = utf8.decode(Uint8List.sublistView(_buffer, 0, end), allowMalformed: true);
    _out.add(BoundedLineSplitter.stripAnsi(_truncated ? '$text…' : text));
    _length = 0;
    _truncated = false;
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) => _out.addError(error, stackTrace);

  @override
  void close() {
    if (_length > 0 || _truncated) _emit();
    _out.close();
  }
}

/// {@template ring_buffer}
/// Keeps the last [capacity] items.
/// {@endtemplate}
final class RingBuffer<T> {
  /// {@macro ring_buffer}
  RingBuffer(this.capacity) : assert(capacity > 0, 'capacity must be positive');

  /// Maximum number of items kept.
  final int capacity;

  final List<T> _items = <T>[];

  /// Adds [item], dropping the oldest one when full.
  void add(T item) {
    if (_items.length == capacity) _items.removeAt(0);
    _items.add(item);
  }

  /// Items from oldest to newest.
  List<T> get items => List<T>.unmodifiable(_items);
}
