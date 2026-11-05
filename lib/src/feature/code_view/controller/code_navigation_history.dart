import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_range.dart';

/// A place in a file: a document line and a UTF-16 column, both 0-based.
typedef CodePlace = ({String path, LspPosition position});

/// {@template code_navigation_history}
/// Where the Code view of a project jumped from: go to definition, a picked reference and ⌘P
/// record the place they leave; back and forward walk them. The newest [limit] are kept.
/// {@endtemplate}
final class CodeNavigationHistory extends ChangeNotifier {
  /// {@macro code_navigation_history}
  CodeNavigationHistory();

  /// Places kept at most.
  static const int limit = 50;

  final List<CodePlace> _back = <CodePlace>[];
  final List<CodePlace> _forward = <CodePlace>[];

  /// There is a place to go back to.
  bool get canGoBack => _back.isNotEmpty;

  /// There is a place to go forward to.
  bool get canGoForward => _forward.isNotEmpty;

  /// A jump leaves [from]: it becomes the place to go back to, and forward is cleared.
  void record(CodePlace from) {
    _back.add(from);
    if (_back.length > limit) _back.removeAt(0);
    _forward.clear();
    notifyListeners();
  }

  /// The place to go back to from [current], which becomes the place to go forward to; `null`
  /// when there is none. A `null` [current] (the last place given could not be opened) is not
  /// kept.
  CodePlace? back(CodePlace? current) => _move(_back, _forward, current);

  /// The place to go forward to from [current], which becomes the place to go back to; `null`
  /// when there is none.
  CodePlace? forward(CodePlace? current) => _move(_forward, _back, current);

  CodePlace? _move(List<CodePlace> from, List<CodePlace> to, CodePlace? current) {
    if (from.isEmpty) return null;
    final place = from.removeLast();
    if (current != null) {
      to.add(current);
      if (to.length > limit) to.removeAt(0);
    }
    notifyListeners();
    return place;
  }
}
