import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/diff_lines_cache.dart';
import 'package:flutter_test/flutter_test.dart';

ToolDiffContent _diff(String oldText, String newText) =>
    ToolDiffContent(path: '/p/a.dart', oldText: oldText, newText: newText);

String _lines(String prefix, int count) =>
    List<String>.generate(count, (i) => '$prefix$i').join('\n');

void main() {
  test('equal diffs are computed once, even as new objects', () {
    final cache = DiffLinesCache(onReady: () {});

    final first = cache.resolve(<ToolDiffContent>[_diff('a', 'b')]);
    final second = cache.resolve(<ToolDiffContent>[_diff('a', 'b')]);

    expect(second.single, same(first.single));
    expect(cache.computeCount, 1);
  });

  test('a changed diff is recomputed and a dropped one is forgotten', () {
    final cache = DiffLinesCache(onReady: () {})
      ..resolve(<ToolDiffContent>[_diff('a', 'b')])
      ..resolve(<ToolDiffContent>[_diff('a', 'c')])
      ..resolve(<ToolDiffContent>[_diff('a', 'b')]);

    expect(cache.computeCount, 3);
  });

  test('a small diff resolves at once', () {
    final cache = DiffLinesCache(onReady: () => fail('nothing runs in the background'));

    expect(cache.resolve(<ToolDiffContent>[_diff('a', 'b')]).single, isNotNull);
  });

  test('a large diff resolves null, then onReady fires once and the lines are there', () async {
    var ready = 0;
    final cache = DiffLinesCache(onReady: () => ready++);
    final diffs = <ToolDiffContent>[_diff(_lines('a', 300), _lines('b', 300))];

    expect(cache.resolve(diffs).single, isNull);
    expect(cache.resolve(diffs).single, isNull);
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(ready, 1);
    expect(cache.resolve(diffs).single, hasLength(600));
    expect(cache.computeCount, 1);
  });

  test('dispose before the diff lands means onReady never fires', () async {
    var ready = 0;
    DiffLinesCache(onReady: () => ready++)
      ..resolve(<ToolDiffContent>[_diff(_lines('a', 300), _lines('b', 300))])
      ..dispose();
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(ready, 0);
  });

  test('a dropped pending diff does not land', () async {
    var ready = 0;
    DiffLinesCache(onReady: () => ready++)
      ..resolve(<ToolDiffContent>[_diff(_lines('a', 300), _lines('b', 300))])
      ..resolve(<ToolDiffContent>[_diff('a', 'b')]);
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(ready, 0);
  });
}
