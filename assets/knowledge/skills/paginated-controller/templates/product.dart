import 'package:flutter/foundation.dart';

/// A row of the paged list.
@immutable
class Product {
  /// Creates a product.
  const Product({required this.id, required this.name});

  /// Server id.
  final int id;

  /// Display name.
  final String name;
}
