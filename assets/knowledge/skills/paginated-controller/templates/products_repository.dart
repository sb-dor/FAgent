import 'product.dart';

/// One page and the server's total.
typedef ProductsPage = (List<Product> products, int total);

/// Reads products page by page. App-global scope values (the selected store, the active
/// organisation) are read by the implementation itself, not passed down by widgets.
abstract interface class IProductsRepository {
  /// [page] is 1-based.
  Future<ProductsPage> products({
    String? query,
    int? categoryId,
    required int page,
    required int pageSize,
  });
}
