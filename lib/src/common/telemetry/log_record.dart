import 'package:flutter_code_agent/src/common/telemetry/clip.dart';
import 'package:flutter_code_agent/src/common/telemetry/redact.dart';
import 'package:l/l.dart';

/// The longest log line, in characters.
const int maxLogLineLength = 1000;

/// A log record in a form that can be sent to another isolate: time (milliseconds, UTC), level,
/// text already clipped to [rawTextLimit], and a flag that the text was clipped.
typedef RawLogLine = (int millis, String level, String text, bool clipped);

/// How many characters of a record's text are taken before cleaning: more than
/// [maxLogLineLength], so that a secret on the boundary of a line is cleaned whole, and no more, so
/// that cleaning does not process megabytes.
const int rawTextLimit = 1100;

/// The record [m] for sending to an isolate and [formatRawLogLine]: not cleaned, cleaning happens
/// there.
RawLogLine rawLogLine(LogMessage m) {
  final message = m.message.toString();
  // The flag is taken from the original length: `cutSafely` can step back one character before a
  // surrogate pair, and the clipped text ends up shorter than the limit.
  return (
    m.timestamp.millisecondsSinceEpoch,
    m.level.prefix,
    cutSafely(message, rawTextLimit),
    message.length > rawTextLimit,
  );
}

/// A log line `2026-11-12T10:15:03.120Z [E] text` from [line]: time in milliseconds UTC, secrets
/// cleaned, line breaks written as `\n`, length not above [maxLogLineLength].
String formatRawLogLine(RawLogLine line) {
  final (millis, level, raw, clipped) = line;
  final time = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toIso8601String();
  var text = redactSecrets(clipForLog(raw)).replaceAll('\r', '').replaceAll('\n', r'\n');
  // The raw text was clipped: the end could land in the middle of an e-mail, a token or a phone that
  // the earlier replacements already shrank and that can no longer be recognised. The tail of the
  // result is dropped.
  if (clipped) {
    text = text.length > rawTailDrop ? '${cutSafely(text, text.length - rawTailDrop)}…' : '…';
  }
  return cutSafely('$time [${level.toUpperCase()}] $text', maxLogLineLength);
}

/// How many characters of the cleaned text are dropped when the raw text was clipped.
const int rawTailDrop = 200;

/// The log lines [lines] joined by a line break. Heavy work: call it in `Isolate.run`.
String formatRawLogLines(Iterable<RawLogLine> lines) => lines.map(formatRawLogLine).join('\n');

/// The log line for the record [m] (see [formatRawLogLine]).
String formatLogLine(LogMessage m) => formatRawLogLine(rawLogLine(m));
