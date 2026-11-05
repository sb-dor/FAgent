import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_range.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CodePlace place(String name, [int line = 0]) =>
      (path: '/p/$name.dart', position: LspPosition(line: line, character: 0));

  test('back walks the recorded places, forward walks them again', () {
    final history = CodeNavigationHistory()
      ..record(place('a'))
      ..record(place('b'));

    expect(history.canGoBack, isTrue);
    expect(history.canGoForward, isFalse);
    expect(history.back(place('c')), place('b'));
    expect(history.back(place('b')), place('a'));
    expect(history.back(place('a')), isNull);
    expect(history.canGoBack, isFalse);
    expect(history.forward(place('a')), place('b'));
    expect(history.forward(place('b')), place('c'));
    expect(history.forward(place('c')), isNull);
  });

  test('recording after a back clears forward', () {
    final history = CodeNavigationHistory()
      ..record(place('a'))
      ..record(place('b'))
      ..back(place('c'))
      ..record(place('b', 3));

    expect(history.canGoForward, isFalse);
    expect(history.back(place('d')), place('b', 3));
  });

  test('the newest 50 places are kept', () {
    final history = CodeNavigationHistory();
    for (var i = 0; i <= CodeNavigationHistory.limit; i++) {
      history.record(place('f$i'));
    }

    var count = 0;
    CodePlace? last;
    var current = place('now');
    for (var previous = history.back(current); previous != null; previous = history.back(current)) {
      last = previous;
      current = previous;
      count++;
    }
    expect(count, 50);
    expect(last, place('f1'));
  });

  test('changes notify listeners', () {
    final history = CodeNavigationHistory();
    var notified = 0;
    history
      ..addListener(() => notified++)
      ..record(place('a'))
      ..back(place('b'));

    expect(notified, 2);
  });
}
