import 'dart:ui';

import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_range.dart';
import 'package:re_editor/re_editor.dart';

/// The document position under [local] (relative to the editor's box) in a monospace editor
/// without word wrap: [gutterWidth] of line numbers, [padding] around the text, [topInset] of a
/// panel above it (find), scrolled by [scrollX] and [scrollY]. A folded block above counts its
/// hidden lines. `null` left of the text, past the end of a line or below the last one.
LspPosition? codePositionAt(
  CodeLineEditingController editing,
  Offset local, {
  required double gutterWidth,
  required double charWidth,
  required double lineHeight,
  required double padding,
  double scrollX = 0,
  double scrollY = 0,
  double topInset = 0,
}) {
  if (charWidth <= 0 || lineHeight <= 0) return null;
  final x = local.dx - gutterWidth - padding + scrollX;
  final y = local.dy - padding - topInset + scrollY;
  if (x < 0 || y < 0) return null;
  final row = (y / lineHeight).floor();
  final codeLines = editing.codeLines;
  if (row >= codeLines.length) return null;
  final column = (x / charWidth).floor();
  if (column >= codeLines[row].text.length) return null;
  final line = codeLines.index2lineIndex(row);
  return LspPosition(line: line < 0 ? row : line, character: column);
}
