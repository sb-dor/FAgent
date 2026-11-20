import 'package:flutter/foundation.dart';

class LocalPagination<T> with ChangeNotifier {
  LocalPagination({required List<T> items, this.itemsPerPage = 20}) : _allItems = items {
    _loadNextPage();
  }

  final List<T> _allItems;
  final int itemsPerPage;

  final List<T> _currentItems = [];
  int _currentPage = 0;
  bool _hasMore = true;

  /// Get currently loaded items
  List<T> get items => _currentItems;

  /// Check if more items are available
  bool get hasMore => _hasMore;

  /// Get total number of items
  int get totalItems => _allItems.length;

  /// Get current loaded items count
  int get loadedItems => _currentItems.length;

  /// Load next page of items
  void loadMore() {
    if (!_hasMore) return;
    _loadNextPage();
  }

  /// Reset pagination to start
  void reset() {
    _currentItems.clear();
    _currentPage = 0;
    _hasMore = true;
    _loadNextPage();
  }

  void resetAllItems({List<T>? items}) {
    _allItems.clear();
    if (items != null) {
      _allItems.addAll(items);
    }
    notifyListeners();
  }

  void _loadNextPage() {
    final startIndex = _currentPage * itemsPerPage;
    final endIndex = startIndex + itemsPerPage;

    if (startIndex >= _allItems.length) {
      _hasMore = false;
      notifyListeners();
      return;
    }

    final nextItems = _allItems.sublist(
      startIndex,
      endIndex > _allItems.length ? _allItems.length : endIndex,
    );

    _currentItems.addAll(nextItems);
    _currentPage++;

    if (_currentItems.length >= _allItems.length) {
      _hasMore = false;
    }
    notifyListeners();
  }
}
