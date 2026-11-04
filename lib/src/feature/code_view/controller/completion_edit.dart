import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_completion.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/snippet_session.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/snippet.dart';
import 'package:re_editor/re_editor.dart';

/// Inserts [completion] at [caret]: it replaces its range (or the word before the caret) with its
/// text or snippet, indented like the line, then applies its additional edits (an `import`).
/// Returns the session of a snippet with tab stops, `null` otherwise (the caret goes after the
/// text).
///
/// Columns are UTF-16 code units, as LSP and Dart strings count them.
SnippetSession? applyCompletion(
  CodeLineEditingController editing,
  DartCompletion completion, {
  required LspPosition caret,
}) {
  final range = completion.edit?.range ?? _wordBefore(editing.codeLines[caret.line].text, caret);
  final indent = RegExp(r'^[ \t]*').stringMatch(editing.codeLines[range.start.line].text) ?? '';
  final snippet = completion.isSnippet
      ? Snippet.parse(completion.insertText).indented(indent)
      : null;
  final text = snippet?.text ?? completion.insertText.replaceAll('\n', '\n$indent');

  // Every edit in the document's first coordinates, from the bottom up, so none moves another.
  final edits = <LspTextEdit>[
    LspTextEdit(range: range, newText: text),
    ...completion.additionalEdits,
  ]..sort((a, b) => _compare(b.range.start, a.range.start));
  for (final edit in edits) {
    editing
      ..selection = CodeLineSelection(
        baseIndex: edit.range.start.line,
        baseOffset: edit.range.start.character,
        extentIndex: edit.range.end.line,
        extentOffset: edit.range.end.character,
      )
      ..replaceSelection(edit.newText);
  }

  final start = _after(range.start, completion.additionalEdits);
  if (snippet != null && snippet.stops.length > 1) {
    return SnippetSession(editing, line: start.line, column: start.character, snippet: snippet);
  }
  final end = snippet?.stops.single.offsets.first.$1 ?? text.length;
  final lines = text.substring(0, end).split('\n');
  editing.selection = CodeLineSelection.collapsed(
    index: start.line + lines.length - 1,
    offset: lines.length == 1 ? start.character + lines.single.length : lines.last.length,
  );
  return null;
}

/// The identifier before [caret] on [line] (letters, digits, `_` and `$`).
LspRange _wordBefore(String line, LspPosition caret) {
  var start = caret.character.clamp(0, line.length);
  while (start > 0 && RegExp(r'[A-Za-z0-9_$]').hasMatch(line[start - 1])) {
    start--;
  }
  return LspRange(
    start: LspPosition(line: caret.line, character: start),
    end: caret,
  );
}

int _compare(LspPosition a, LspPosition b) =>
    a.line != b.line ? a.line.compareTo(b.line) : a.character.compareTo(b.character);

/// Where [position] is after the [edits] that come before it.
LspPosition _after(LspPosition position, List<LspTextEdit> edits) {
  var line = position.line;
  var column = position.character;
  for (final edit in edits) {
    if (_compare(edit.range.end, position) > 0) continue;
    final added = '\n'.allMatches(edit.newText).length;
    line += added - (edit.range.end.line - edit.range.start.line);
    if (edit.range.end.line == position.line) {
      final last = edit.newText.split('\n').last;
      column =
          (added == 0 ? edit.range.start.character + last.length : last.length) +
          (position.character - edit.range.end.character);
    }
  }
  return LspPosition(line: line, character: column);
}
