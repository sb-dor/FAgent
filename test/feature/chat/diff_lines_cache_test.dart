import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/diff_lines_cache.dart';
import 'package:flutter_test/flutter_test.dart';

ToolDiffContent _diff(String oldText, String newText) =>
    ToolDiffContent(path: '/p/a.dart', oldText: oldText, newText: newText);

void main() {
  test('equal diffs are computed once, even as new objects', () {
    final cache = DiffLinesCache();

    final first = cache.resolve(<ToolDiffContent>[_diff('a', 'b')]);
    final second = cache.resolve(<ToolDiffContent>[_diff('a', 'b')]);

    expect(second.single, same(first.single));
    expect(cache.computeCount, 1);
  });

  test('a changed diff is recomputed and a dropped one is forgotten', () {
    final cache = DiffLinesCache()
      ..resolve(<ToolDiffContent>[_diff('a', 'b')])
      ..resolve(<ToolDiffContent>[_diff('a', 'c')])
      ..resolve(<ToolDiffContent>[_diff('a', 'b')]);

    expect(cache.computeCount, 3);
  });
}
