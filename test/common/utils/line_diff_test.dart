import 'package:flutter_code_agent/src/common/utils/line_diff.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _render(String? oldText, String newText) =>
    LineDiff.compute(oldText, newText).map((l) => '$l').toList();

void main() {
  test('a new file is all additions', () {
    expect(_render(null, 'a\nb'), <String>['+a', '+b']);
  });

  test('a changed line is removed then added between kept lines', () {
    expect(_render('a\nb\nc', 'a\nB\nc'), <String>[' a', '-b', '+B', ' c']);
  });

  test('insertions and deletions keep the common lines', () {
    expect(_render('a\nc\nd', 'a\nb\nc'), <String>[' a', '+b', ' c', '-d']);
    expect(LineDiff.stats(LineDiff.compute('a\nc\nd', 'a\nb\nc')), (added: 1, removed: 1));
  });

  test('huge inputs fall back to remove-all, add-all', () {
    final big = List<String>.generate(2100, (i) => 'line $i').join('\n');
    final lines = LineDiff.compute(big, '$big\nextra');
    expect(lines.where((l) => l.kind == DiffLineKind.same), isEmpty);
    expect(lines.length, 2100 + 2101);
  });
}
