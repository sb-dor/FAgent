
import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_range.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_pointer_position.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  const gutter = 40.0;
  const char = 8.0;
  const line = 20.0;
  const padding = 5.0;

  CodeLineEditingController editing() => CodeLineEditingController(
    codeLines: CodeLines.fromText(
      'void a() {\n  first();\n  second();\n}\nvoid b() {\n  third();\n}\n',
    ),
  );

  /// The middle of [column] on visual [row].
  Offset at(int row, int column) =>
      Offset(gutter + padding + column * char + char / 2, padding + row * line + line / 2);

  LspPosition? position(
    CodeLineEditingController editing,
    Offset local, {
    double scrollX = 0,
    double scrollY = 0,
    double topInset = 0,
  }) => codePositionAt(
    editing,
    local,
    gutterWidth: gutter,
    charWidth: char,
    lineHeight: line,
    padding: padding,
    scrollX: scrollX,
    scrollY: scrollY,
    topInset: topInset,
  );

  test('a point on the text gives its document line and column', () {
    expect(position(editing(), at(1, 4)), const LspPosition(line: 1, character: 4));
  });

  test('vertical scroll moves the line', () {
    expect(
      position(editing(), at(2, 2), scrollY: 2 * line),
      const LspPosition(line: 4, character: 2),
    );
  });

  test('horizontal scroll moves the column', () {
    expect(
      position(editing(), at(1, 4), scrollX: 3 * char),
      const LspPosition(line: 1, character: 7),
    );
  });

  test('the find panel above the text shifts it down', () {
    final shifted = at(1, 4) + const Offset(0, 44);
    expect(position(editing(), shifted, topInset: 44), const LspPosition(line: 1, character: 4));
  });

  test('a folded block above counts its hidden lines', () {
    final folded = editing()..collapseChunk(0, 3);
    // The fold hides lines 1–2: visual line 2 is document line 4 (`void b() {`).
    expect(position(folded, at(2, 2)), const LspPosition(line: 4, character: 2));
  });

  test('past the end of a line, left of the text or below the last line is null', () {
    expect(position(editing(), at(0, 40)), isNull);
    expect(position(editing(), const Offset(gutter - 2, padding + line / 2)), isNull);
    expect(position(editing(), at(30, 0)), isNull);
  });
}
