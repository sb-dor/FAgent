import 'package:control/control.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'local_pagination_util.dart';
import 'product.dart';
import 'products_repository.dart';

part 'products_controller.freezed.dart';

@freezed
sealed class ProductsState with _$ProductsState {
  const ProductsState._();

  const factory ProductsState.initial() = Products$InitialState;

  const factory ProductsState.inProgress() = Products$InProgressState;

  const factory ProductsState.error({Object? error}) = Products$ErrorState;

  /// [page] is the NEXT page to request; [query] is the active search term.
  const factory ProductsState.completed(
    List<Product> products,
    int page,
    bool hasMore,
    int total,
    String query,
  ) = Products$CompletedState;

  /// For the variants that do not declare [products]: `completed`'s own field wins over this
  /// getter, so a `switch (this)` arm for `completed` here would be dead code.
  List<Product> get products => const <Product>[];

  /// Same rule as [products].
  bool get hasMore => false;
}

/// Loads the first page and appends the next ones. The cursor lives in the `completed` state,
/// so a failed page can never leave a hole. The controller keeps no query or filter field.
final class ProductsController extends StateController<ProductsState>
    with SequentialControllerHandler {
  ProductsController({
    required this._productsRepository,
    this._localPaginationUtil = const LocalPaginationUtil(),
    this._limitInPage = 50,
    super.initialState = const ProductsState.initial(),
  });

  final IProductsRepository _productsRepository;
  final LocalPaginationUtil _localPaginationUtil;
  final int _limitInPage;

  /// Page 1; resets the list.
  void load({String query = '', int? categoryId}) => handle(() async {
    setState(const ProductsState.inProgress());
    final (items, total) = await _productsRepository.products(
      categoryId: categoryId,
      query: query,
      page: 1,
      pageSize: _limitInPage,
    );
    setState(ProductsState.completed(items, _nextPage(items, 1), _hasMore(items), total, query));
  }, error: (error, stackTrace) async => setState(ProductsState.error(error: error)));

  /// Appends the next page. It does not set `inProgress`, so the rows stay on screen.
  void paginate({String query = '', int? categoryId}) => handle(() async {
    final current = state;
    if (current is! Products$CompletedState || !current.hasMore) return;
    final (next, total) = await _productsRepository.products(
      categoryId: categoryId,
      query: query,
      page: current.page,
      pageSize: _limitInPage,
    );
    setState(
      ProductsState.completed(
        [...current.products, ...next],
        _nextPage(next, current.page),
        _hasMore(next),
        total,
        query,
      ),
    );
  }, error: (error, stackTrace) async => setState(ProductsState.error(error: error)));

  int _nextPage(List<Product> list, int page) => _localPaginationUtil.checkIsListHasMorePageInt(
    list: list,
    page: page,
    limitInPage: _limitInPage,
  );

  bool _hasMore(List<Product> list) =>
      _localPaginationUtil.checkIsListHasMorePageBool(list: list, limitInPage: _limitInPage);
}
