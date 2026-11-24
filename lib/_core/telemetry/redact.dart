import 'package:flutter_code_agent/_core/telemetry/clip.dart';

/// What `redactSecrets` replaces a secret with.
const String redactedMark = '[REDACTED]';

const String _tokenChars = '[A-Za-z0-9._~+/=-]';

final RegExp _bearer = RegExp('(Bearer\\s+)$_tokenChars+', caseSensitive: false);

// A field value: quoted (with escapes), unquoted up to a separator, or an unclosed quote.
const String _value =
    r'''(?:\[REDACTED\]|"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|[^\s,;&}\])"']+|["'][^\n]*)''';

// Left boundary `(?<![A-Za-z_])`: the search starts only at the beginning of a word, otherwise it is
// quadratic on a long run of letters. «PIN 1234» without a colon is left alone: it is ambiguous.
const String _secretHead =
    '''(?<![A-Za-z_])(["']?[A-Za-z_]*(?:token|key|password|pin|secret)'''
    r'''(?:_?(?:code|hash))?["']?\s*[:=]\s*)''';
final RegExp _secretField = RegExp('$_secretHead$_value', caseSensitive: false);

// A phone in a field: the value is cleaned in any format, up to the end of the line or a separator.
// `phone|phoneNumber|tel|telephone|mobile|cellphone` after a non-letter (`user_phone` yes,
// `microphone` no) and camelCase/PascalCase `homePhone`, `HomePhone`: the second expression is case
// sensitive, so `headphone` does not match.
const String _phoneValue =
    r'''(?:\[REDACTED\]|"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|[^\n,;&}\]"']+)''';
final RegExp _phoneField = RegExp(
  r'''(?<![A-Za-z])(["']?(?:phone(?:_?number)?|tel(?:ephone)?|mobile|cell_?phone)["']?\s*[:=]\s*)'''
  '$_phoneValue',
  caseSensitive: false,
);
final RegExp _phoneFieldCamel = RegExp(
  r'''(?<![A-Za-z_])(["']?[A-Za-z]*Phone(?:Number)?["']?\s*[:=]\s*)'''
  '$_phoneValue',
);

// Keys that coding agents print in free text, without a field name. Each pattern starts at a token
// boundary `(?<![A-Za-z0-9_-])`, so the scan stays linear on long runs of data.
final RegExp _anthropicKey = RegExp('(?<![A-Za-z0-9_-])sk-ant-[A-Za-z0-9_-]{16,}');
final RegExp _openAiKey = RegExp('(?<![A-Za-z0-9_-])sk-(?:proj-)?[A-Za-z0-9_-]{20,}');
final RegExp _githubToken = RegExp('(?<![A-Za-z0-9_-])gh[pousr]_[A-Za-z0-9]{20,}');
final RegExp _githubPat = RegExp('(?<![A-Za-z0-9_-])github_pat_[A-Za-z0-9_]{20,}');
final RegExp _googleKey = RegExp('(?<![A-Za-z0-9_-])AIza[A-Za-z0-9_-]{30,}');
final RegExp _slackToken = RegExp('(?<![A-Za-z0-9_-])xox[abp]-[A-Za-z0-9-]{10,}');

// A random 32-byte secret (43 base64url characters) in free text, without a field name. Starts only
// at a token boundary: the expression is linear on solid data.
final RegExp _token43 = RegExp('(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{43}(?![A-Za-z0-9_-])');
final RegExp _tokenMark = RegExp('[0-9_-]');
final RegExp _hexOnly = RegExp(r'^[0-9a-fA-F]+$');

// The user name in a path: `C:\Users\<name>`, `/Users/<name>`, `/home/<name>`, `users` in any case,
// a single or double separator (`C:\\Users\\x` in JSON). The path does not start inside a word:
// `package:app/src/home/x.dart` is not a user path. The name runs to the next separator (it may
// contain a space, `John Smith`); with no separator further on, to the first space.
final RegExp _userPath = RegExp(
  r'''((?:(?<![A-Za-z0-9_.-])[A-Za-z]:[\\/]{1,2}[Uu][Ss][Ee][Rr][Ss][\\/]{1,2})|(?:(?<![A-Za-z0-9_.-])/(?:[Uu]sers|home)/))'''
  r'''((?:[^\\/"'\r\n]*[^\\/"'\r\n\s](?=[\\/])|[^\\/\s"':]+))''',
);

// Authorization: the scheme stays, the token is cleaned.
final RegExp _authorization = RegExp(
  r'''(?<![A-Za-z_])(["']?authorization["']?\s*[:=]\s*["']?)'''
  r'''([^\s"',;]+)(?:([ \t]+)([^\s"',;]+))?''',
  caseSensitive: false,
);

const Set<String> _schemes = {'bearer', 'basic', 'digest'};

final RegExp _phone = RegExp(r'\+\d[\d\s().-]{7,}\d');

// Starts at a word boundary: otherwise the search on a long string without `@` is quadratic.
final RegExp _email = RegExp(
  r'(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+',
);

/// Text for the log and the queue: clip with [clipForLog], clean with [redactSecrets], clip again
/// (the `[REDACTED]` replacement can make the text longer).
String cleanForLog(String text) => clipForLog(redactSecrets(clipForLog(text)));

/// Replaces secrets and personal data in [text] with `[REDACTED]`: `Bearer …`, the values of fields
/// `token|key|password|pin|secret`, API keys of coding agents (`sk-ant-…`, `sk-…`, `ghp_…`,
/// `github_pat_…`, `AIza…`, `xoxb-…`), the user name in paths, phones and e-mails.
/// Certificate fingerprints stay.
///
/// A string longer than [logClipLength] characters is clipped with [clipForLog] (with an ellipsis,
/// without splitting a surrogate pair): regular expressions overflow the stack on megabytes of
/// solid data.
String redactSecrets(String text) {
  if (text.length <= logClipLength) {
    return _redact(text);
  }
  return text.split('\n').map((line) => _redact(clipForLog(line))).join('\n');
}

String _redact(String text) {
  return text
      .replaceAllMapped(_authorization, (m) {
        final first = m[2]!;
        final second = m[4];
        if (_schemes.contains(first.toLowerCase()) && second != null) {
          return '${m[1]}$first${m[3]}${second == redactedMark ? second : redactedMark}';
        }
        if (first == redactedMark) {
          return m[0]!;
        }
        return '${m[1]}$redactedMark${m[3] ?? ''}${second ?? ''}';
      })
      .replaceAll(_anthropicKey, redactedMark)
      .replaceAll(_openAiKey, redactedMark)
      .replaceAll(_githubToken, redactedMark)
      .replaceAll(_githubPat, redactedMark)
      .replaceAll(_googleKey, redactedMark)
      .replaceAll(_slackToken, redactedMark)
      .replaceAllMapped(
        _token43,
        // Pure hex and a word of letters only (a drift identifier) are not a token: a token has a digit,
        // `-` or `_`.
        (m) => _hexOnly.hasMatch(m[0]!) || !_tokenMark.hasMatch(m[0]!) ? m[0]! : redactedMark,
      )
      .replaceAllMapped(_userPath, (m) => '${m[1]}$redactedMark')
      .replaceAllMapped(_bearer, (m) => '${m[1]}$redactedMark')
      .replaceAllMapped(_secretField, _mask)
      .replaceAllMapped(_phoneField, _mask)
      .replaceAllMapped(_phoneFieldCamel, _mask)
      .replaceAll(_phone, redactedMark)
      .replaceAll(_email, redactedMark);
}

// Keeps the field name and the quotes, replaces the value with the mark.
String _mask(Match m) {
  final prefix = m[1]!;
  final value = m[0]!.substring(prefix.length);
  final quote = value.isNotEmpty && (value[0] == '"' || value[0] == "'") ? value[0] : '';
  return '$prefix$quote$redactedMark$quote';
}
