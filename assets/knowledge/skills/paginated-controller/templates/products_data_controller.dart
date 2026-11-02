import 'package:flutter/foundation.dart';

/// The active filter. It lives here, not in the async controller; the config widget reads it and
/// passes it to `load(...)` / `paginate(...)` on every call.
class ProductsDataController with ChangeNotifier {
  int? _filterId;

  /// The selected category, or `null`.
  int? get filterId => _filterId;

  /// Selects a category and notifies listeners when it changed.
  void setFilter(int? value) {
    if (_filterId == value) return;
    _filterId = value;
    notifyListeners();
  }
}
