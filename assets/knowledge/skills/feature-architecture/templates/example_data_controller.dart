import 'package:flutter/foundation.dart';

/// UI state of the example screen: the search text. Not asynchronous, so a plain [ChangeNotifier]
/// rather than a `StateController`. Widgets listen with `ListenableBuilder`.
class ExampleDataController with ChangeNotifier {
  String _query = '';

  /// The current search text.
  String get query => _query;

  /// Sets the search text and notifies listeners when it changed.
  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }
}
