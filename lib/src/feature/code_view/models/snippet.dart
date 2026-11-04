import 'package:meta/meta.dart';

/// {@template snippet_stop}
/// A tab stop of a [Snippet]: where it sits in the text, once per mirror (`${1:name}` used twice).
/// {@endtemplate}
@immutable
final class SnippetStop {
  /// {@macro snippet_stop}
  const SnippetStop({required this.index, required this.offsets});

  /// `1`, `2`, … in Tab order; `0` is where the caret ends.
  final int index;

  /// `(start, end)` in the snippet's text, in order; every one shows the same text.
  final List<(int, int)> offsets;

  @override
  String toString() => 'SnippetStop($index, $offsets)';
}

/// {@template snippet}
/// An LSP snippet body (`$1`, `${1:name}`, `${1|a,b|}`, `$0`) as the text it inserts and its tab
/// stops, `1…n` then `0`.
/// {@endtemplate}
@immutable
final class Snippet {
  /// {@macro snippet}
  const Snippet({required this.text, required this.stops});

  /// Parses an LSP snippet [body]. `\$`, `\}` and `\\` are literal; a choice keeps its first
  /// value; a snippet without `$0` ends at its end.
  factory Snippet.parse(String body) {
    final text = StringBuffer();
    final offsets = <int, List<(int, int)>>{};
    var i = 0;

    void readInto(StringBuffer out, {required bool nested}) {
      while (i < body.length) {
        final char = body[i];
        if (char == r'\' && i + 1 < body.length && r'$}\'.contains(body[i + 1])) {
          out.write(body[i + 1]);
          i += 2;
        } else if (nested && char == '}') {
          return;
        } else if (char == r'$') {
          final simple = RegExp(r'\$(\d+)').matchAsPrefix(body, i);
          final braced = RegExp(r'\$\{(\d+)').matchAsPrefix(body, i);
          if (simple != null) {
            // One buffer for the whole text, nested placeholders too: its length is the offset.
            (offsets[int.parse(simple.group(1)!)] ??= <(int, int)>[]).add((out.length, out.length));
            i = simple.end;
          } else if (braced != null) {
            final index = int.parse(braced.group(1)!);
            i = braced.end;
            final start = out.length;
            if (i < body.length && body[i] == '|') {
              final end = body.indexOf('|}', i);
              final choice = (end < 0 ? body.substring(i + 1) : body.substring(i + 1, end))
                  .split(',')
                  .first;
              out.write(choice);
              i = end < 0 ? body.length : end + 2;
            } else {
              if (i < body.length && body[i] == ':') i++;
              readInto(out, nested: true);
              if (i < body.length && body[i] == '}') i++;
            }
            (offsets[index] ??= <(int, int)>[]).add((start, out.length));
          } else {
            // A variable (`$TM_SELECTED_TEXT`) or a lone `$`: no selection to put there.
            final variable = RegExp(r'\$(\{[A-Za-z_]+[^}]*\}|[A-Za-z_]+)').matchAsPrefix(body, i);
            if (variable != null) {
              i = variable.end;
            } else {
              out.write(char);
              i++;
            }
          }
        } else {
          out.write(char);
          i++;
        }
      }
    }

    readInto(text, nested: false);
    final result = text.toString();
    final indexes = offsets.keys.where((index) => index != 0).toList()..sort();
    return Snippet(
      text: result,
      stops: <SnippetStop>[
        for (final index in indexes) SnippetStop(index: index, offsets: offsets[index]!),
        SnippetStop(index: 0, offsets: offsets[0] ?? <(int, int)>[(result.length, result.length)]),
      ],
    );
  }

  /// What is inserted.
  final String text;

  /// The tab stops, `1…n` then `0` (always there).
  final List<SnippetStop> stops;

  /// The snippet with [indent] after every newline (the indent of the line it goes into), its stops
  /// moved along.
  Snippet indented(String indent) {
    if (indent.isEmpty || !text.contains('\n')) return this;
    int shift(int offset) =>
        offset + indent.length * '\n'.allMatches(text.substring(0, offset)).length;
    return Snippet(
      text: text.replaceAll('\n', '\n$indent'),
      stops: <SnippetStop>[
        for (final stop in stops)
          SnippetStop(
            index: stop.index,
            offsets: <(int, int)>[
              for (final (start, end) in stop.offsets) (shift(start), shift(end)),
            ],
          ),
      ],
    );
  }

  @override
  String toString() => 'Snippet(${text.length} chars, $stops)';
}
