import 'package:control/control.dart';
import 'package:flutter/material.dart';

import 'products_controller.dart';

/// Fires [onLoadMore] near the bottom of the list. `controller.isProcessing` guards against a
/// burst of scroll notifications starting several fetches.
class ProductsListWidget extends StatefulWidget {
  const ProductsListWidget({super.key, required this.controller, required this.onLoadMore});

  final ProductsController controller;

  /// Typically `() => controller.paginate(categoryId: dataController.filterId)`.
  final VoidCallback onLoadMore;

  @override
  State<ProductsListWidget> createState() => _ProductsListWidgetState();
}

class _ProductsListWidgetState extends State<ProductsListWidget> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 200) return;
    if (widget.controller.isProcessing) return;
    widget.onLoadMore();
  }

  @override
  Widget build(BuildContext context) {
    return StateConsumer<ProductsController, ProductsState>(
      controller: widget.controller,
      builder: (context, state, child) => switch (state) {
        Products$InitialState() ||
        Products$InProgressState() => const Center(child: CircularProgressIndicator()),
        Products$ErrorState() => const Center(child: Icon(Icons.error_outline)),
        Products$CompletedState(:final products, :final hasMore) => ListView.builder(
          controller: _scrollController,
          itemCount: products.length + (hasMore ? 1 : 0),
          itemBuilder: (context, index) => index < products.length
              ? ListTile(title: Text(products[index].name))
              : const Center(child: CircularProgressIndicator()),
        ),
      },
    );
  }
}
