import 'dart:math' as math;

import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_range.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/dart_analysis_repository.dart';
import 'package:re_editor/re_editor.dart';

/// Applies the analysis's [edits] (in document coordinates, none overlapping) to [editing] as one
/// undo step, every fold opened first. The caret stays on the same code: an edit before it shifts
/// it, one around it keeps it as far into the new text as it was into the old. The file's line
/// break stays as it was.
void applyTextEdits(CodeLineEditingController editing, List<LspTextEdit> edits) {
  if (edits.isEmpty) return;
  unfoldAllChunks(editing);
  final lines = <String>[
    for (var i = 0; i < editing.codeLines.length; i++) editing.codeLines[i].text,
  ];
  final starts = <int>[0];
  for (final line in lines) {
    starts.add(starts.last + line.length + 1);
  }
  final text = lines.join('\n');
  int offsetOf(LspPosition position) {
    if (position.line >= lines.length) return text.length;
    return starts[position.line] + position.character.clamp(0, lines[position.line].length);
  }

  final selection = editing.selection;
  final caret = offsetOf(
    LspPosition(line: selection.extentIndex, character: selection.extentOffset),
  );
  final ranges = <(int, int, String)>[
    for (final edit in edits)
      (offsetOf(edit.range.start), offsetOf(edit.range.end), edit.newText.replaceAll('\r\n', '\n')),
  ]..sort((a, b) => b.$1.compareTo(a.$1));

  var result = text;
  var newCaret = caret;
  for (final (start, end, replacement) in ranges) {
    result = result.replaceRange(start, end, replacement);
    // From the bottom up: an edit below the caret moves nothing before it.
    if (end <= caret) {
      newCaret += replacement.length - (end - start);
    } else if (start < caret) {
      // Edits below the caret came first and moved nothing: it is still at [caret].
      newCaret = start + math.min(caret - start, replacement.length);
    }
  }
  if (result == text) return;

  final before = result.substring(0, newCaret.clamp(0, result.length)).split('\n');
  editing.runRevocableOp(() {
    editing.value = CodeLineEditingValue(
      codeLines: CodeLines.fromText(result),
      selection: CodeLineSelection.collapsed(index: before.length - 1, offset: before.last.length),
    );
  });
}

/// Formats the Dart text [document] with the [analysis]: `false`, with nothing changed, for a
/// document that is not Dart text or is read-only, when the analysis has no edits (no server, a
/// syntax error, already formatted), and when the text changed while it was asked.
Future<bool> formatDocument(CodeDocument document, IDartAnalysisRepository analysis) async {
  if (document.kind != CodeDocumentKind.text ||
      document.readOnly ||
      !document.path.endsWith('.dart')) {
    return false;
  }
  final editing = document.editing;
  final lines = editing.codeLines;
  final edits = await analysis.format(document.path, editing.text);
  if (edits == null || edits.isEmpty || !identical(lines, editing.codeLines)) return false;
  applyTextEdits(editing, edits);
  return !identical(lines, editing.codeLines);
}
