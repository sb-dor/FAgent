---
name: controllers
description: "StateController with freezed states and handlers, one concern per controller, mutation features and paginated lists."
---

# Controllers

## Rules

- Extend `StateController<XState>` and change state through `handle(() async {...}, error: ...)`.
  States are freezed: `initial`, `inProgress`, `error`, `completed`.
- `SequentialControllerHandler` for load/watch and pagination.
  `DroppableControllerHandler` for mutations (create, save, delete).
- One controller, one domain concern. Split when the async parts need different handlers or have
  independent `inProgress`/`error` state.
- Controllers of one feature never import each other. Widgets coordinate them with `addListener`
  or the `listener` of `StateConsumer`.
- A controller keeps no query or filter field. The widget passes the filter on every call.
- Dialogs with an async action: `PopScope(canPop: state is! ...InProgressState)`.

## Controller patterns

### Single responsibility

Every feature folder and every controller has one domain responsibility. A responsibility is not a
single function; it is a single domain concern.

A controller may have several methods when they serve the same concern. An
`AuthenticationController` with `signIn`, `signOut` and `checkToken` is fine: all three answer "is
this user authenticated?". Splitting them into three features is over-engineering.

Split when two things have genuinely independent UI state machines or no logical connection at the
domain level. Quick replies are three features:

```
example_list/       "provide the reactive list to the UI"
example_creation/   "manage the create/edit form lifecycle (inProgress, completed, error)"
example_deletion/   "manage the delete confirmation lifecycle (inProgress, completed, error)"
```

The creation form and the deletion dialog each need their own `inProgress` / `completed` / `error`.
If they shared one controller, a deletion in progress could overwrite the form's state and break
`PopScope`. The list (watching a stream) has no state overlap with either mutation.

### Mutation features (creation, deletion)

```
feature_name/
├── data/feature_name_repository.dart       (interface + impl)
├── controller/feature_name_controller.dart (freezed states + handle())
└── widgets/
    ├── feature_name_config_widget.dart     (InheritedWidget scope + static factory)
    └── feature_name_dialog_widget.dart     (form / confirmation UI)
```

The controller uses `DroppableControllerHandler`, so duplicate taps are dropped. Templates:
`example_creation_controller.dart`, `example_deletion_controller.dart` and their repository
interfaces in `example_mutation_repositories.dart` (in Examples below; adjust the imports to the layout):

```dart
class ExampleCreationController extends StateController<ExampleCreationState>
    with DroppableControllerHandler {
  void save({required String title, required String content, Example? existing}) =>
      handle(() async {
        setState(const ExampleCreationState.inProgress());
        final result = await _repo.save(title: title, content: content, existing: existing);
        setState(ExampleCreationState.completed(result));
      }, error: (e, st) async => setState(const ExampleCreationState.error()));
}
```

Use `SequentialControllerHandler` for load/watch.

The config widget owns the controller lifecycle and exposes a static factory so callers need one
line:

```dart
class ExampleCreationConfigWidget extends StatefulWidget {
  static Future<void> showCreationDialog(BuildContext context, {Example? existing}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => ExampleCreationConfigWidget(
        builder: (_) => ExampleCreationDialogWidget(existing: existing),
      ),
    );
  }
  // ...
}
```

The dialog widget closes itself with `StateConsumer` and blocks dismissal mid-flight with
`PopScope` (`example_deletion_dialog.dart`):

```dart
StateConsumer<ExampleCreationController, ExampleCreationState>(
  controller: _controller,
  listener: (context, controller, oldState, newState) {
    if (newState is ExampleCreation$CompletedState) Navigator.pop(context);
  },
  builder: (context, state, child) => PopScope(
    canPop: state is! ExampleCreation$InProgressState,
    child: AlertDialog(...),
  ),
);
```

The calling site only uses the factory:

```dart
ExampleCreationConfigWidget.showCreationDialog(context);
ExampleCreationConfigWidget.showCreationDialog(context, existing: example);
ExampleDeletionConfigWidget.showDeletionDialog(context, example);
```

### Rules

- Group by domain concern, not by function count.
- Create and update may share one feature when they write the same record. The create-vs-update
  decision belongs in the repository, not the controller or widget.
- Split when UI states are independent: if two operations each show their own
  `inProgress` / `completed` / `error` at once or to different widgets, they need separate
  controllers and features.
- Config widgets own the controller lifecycle: created in `initState`, disposed in `dispose`,
  nowhere else.
- Static factory methods on config widgets keep wiring internal and give callers a one-line API.
- `DroppableControllerHandler` for mutations, `SequentialControllerHandler` for load/watch.
- `PopScope(canPop: state is! ...InProgressState)` on every dialog with an async operation.

### Multiple controllers in one feature

Split a feature's controllers when its async operations either need different concurrency handlers
(`Droppable` vs `Sequential`) or keep independent state that must update simultaneously without one
overwriting the other.

```
call/controller/
├── call_controller.dart
├── call_media_controller.dart
└── call_members_controller.dart
```

Each handles one async concern. `CallMediaController` is `Droppable`, so rapid taps are dropped.
`CallController` is `Sequential`, so join and leave never interleave. One shared controller would
force a single strategy on all three.

#### Coordination rule

Controllers in the same feature never import or depend on each other. The widget layer coordinates
them with `addListener` or the `listener` of `StateConsumer`: it reacts to one controller's state
and calls methods on another.

```dart
callController.addListener(() {
  if (callController.state is Call$IdleState) {
    callMembersController.reset();
    callMediaController.reset();
  }
});
```

## Paginated controllers

Every paged list follows one shape. Copy it rather than inventing a variant: the differences
between hand-rolled paginators are where the silent bugs live.

### Rules

1. **The cursor lives in the state, never in a controller field.** `page` and `hasMore` are
   constructor arguments of the `completed` state. A mutable `int _page` on the controller can be
   advanced past a page that failed, which leaves a permanent, invisible hole in the list.
2. **Everything the controller depends on arrives through the constructor**: repository, page size,
   pagination util, initial filter. A dependency built inside the controller cannot be substituted
   in a test or varied per screen.
3. **`page` in the completed state is the next page to request**, not the one just loaded.
   `LocalPaginationUtil.checkIsListHasMorePageInt` computes it. The util lives at
   `lib/src/common/utils/local_pagination_util.dart` and infers "has more" from page fullness: a full
   page (length == `limitInPage`) means another page probably exists, a short page means the end. No
   server `total` is required; keep `total` in the state only when the UI shows a count.
4. **Two methods, never one.** `load(...)` fetches page 1 and resets the state; `paginate(...)`
   appends the next page. Both run through the same `SequentialControllerHandler`, so they never
   interleave and a second page request arriving mid-flight runs instead of being dropped.
5. **The async controller stays query-stateless.** No `_query`, `_from`, `_storeUid` fields. The
   active query and filters live in a `ChangeNotifier` data controller under `widgets/controllers/`;
   the config widget reads them and passes them to `load(...)` / `paginate(...)` on every call.
   App-global scope values such as `store_uid` are not passed at all: the repository reads them.
   Echoing the active query in the `completed` state is a display concern and fine; storing it as a
   mutable controller field is not.

### Template

`products_controller.dart` (state, `load`, `paginate`), `products_repository.dart` (returns the page
and the server total as a record, `typedef ProductsPage = (List<Product> products, int total)`),
`local_pagination_util.dart`, `product.dart`, `products_data_controller.dart`,
`products_list_widget.dart`. `paginate`'s `hasMore` guard is what makes the repeated firing of a
bottom-of-list scroll notification safe.

### Convenience getters on the state

Put shared accessors on the sealed state, not the controller (`allCustomers`, `selectableCustomers`).
Add `const XxxState._();` to the union so it can carry methods.

**A getter that shares a name with a variant's field is overridden by that field.** `completed`
declares `products` / `page` / `hasMore`; a base getter of the same name is reached only for the
variants that do not declare it. Writing it as an exhaustive `switch (this)` with a `completed` arm
compiles and reads plausibly, and that arm is dead code. Write the body as the answer for the
variants without the field:

```dart
List<Product> get products => const <Product>[];   // completed's field wins
bool get hasMore => false;
```

Give a getter a different name from the fields when it computes across them (`allCustomers` reads
`customers`).

### Triggering `paginate` from the widget

The widget fires `paginate()` from a `ScrollController` near the bottom of the list, guarded by
`controller.isProcessing` (exposed by `SequentialControllerHandler`) so a burst of scroll
notifications starts one fetch. Show a footer spinner while `hasMore`.

The filter lives in the data controller; the config widget owns both controllers and passes the
filter on every call:

```dart
// widgets/controllers/example_data_controller.dart
class ExampleDataController with ChangeNotifier {
  int? _filterId;
  int? get filterId => _filterId;
  void setFilter(int? value) {
    if (_filterId == value) return;
    _filterId = value;
    notifyListeners();
  }
}

// example_config_widget.dart
void load()     => controller.load(filterId: dataController.filterId);
void loadMore() => controller.paginate(filterId: dataController.filterId);
```

### Non-paginated lists

An endpoint that truly returns one fixed or capped list (a small summary feed, a hard top-N with no
page controls) does not use this pattern: fetch it in one `load()` and render it, with no
`paginate()`. When in doubt, add pagination; most list endpoints accept `page` / `page_size`.

### Refinements, where the screen earns them

- **`paginate` must not set `inProgress`.** Leave the `completed` state until the next page lands:
  an `inProgress` with no rows blanks the list mid-scroll. `load` is the opposite and should clear.
- **A pagination failure clears the whole list.** The cursor lives on `completed`, so an error takes
  it with it and the failed page cannot be resumed; recovery is `load()` from page 1. A page of a
  list with the rest silently missing reads as the whole list. Restoring the previous `completed`
  state on a `paginate` failure is acceptable only when the screen shows the failure explicitly
  (an inline retry footer). Silently keeping a truncated list with no error affordance is the case
  this rule prevents.
- **Echo the active filter/query in the completed state** when the app bar must show how many facets
  are on. The controller still takes the initial one through its constructor and falls back to it
  outside `completed`.

## Examples

Whole files, one per block; put each where the layout above says and adjust the imports.

### `example_creation_controller.dart`

```dart
// file: example_creation_controller.dart
import 'package:control/control.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'example.dart';
import 'example_mutation_repositories.dart';

part 'example_creation_controller.freezed.dart';

@freezed
sealed class ExampleCreationState with _$ExampleCreationState {
  const factory ExampleCreationState.initial() = ExampleCreation$InitialState;

  const factory ExampleCreationState.inProgress() = ExampleCreation$InProgressState;

  const factory ExampleCreationState.error({Object? error}) = ExampleCreation$ErrorState;

  const factory ExampleCreationState.completed(Example example) = ExampleCreation$CompletedState;
}

/// Saves the create/edit form. A mutation: [DroppableControllerHandler] drops a second tap while
/// the first save is running.
final class ExampleCreationController extends StateController<ExampleCreationState>
    with DroppableControllerHandler {
  ExampleCreationController({
    required this._repository,
    super.initialState = const ExampleCreationState.initial(),
  });

  final IExampleCreationRepository _repository;

  void save({required String title, required String content, Example? existing}) =>
      handle(() async {
        setState(const ExampleCreationState.inProgress());
        final result = await _repository.save(title: title, content: content, existing: existing);
        setState(ExampleCreationState.completed(result));
      }, error: (error, stackTrace) async => setState(ExampleCreationState.error(error: error)));
}
```

### `example_deletion_controller.dart`

```dart
// file: example_deletion_controller.dart
import 'package:control/control.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'example_mutation_repositories.dart';

part 'example_deletion_controller.freezed.dart';

@freezed
sealed class ExampleDeletionState with _$ExampleDeletionState {
  const factory ExampleDeletionState.initial() = ExampleDeletion$InitialState;

  const factory ExampleDeletionState.inProgress() = ExampleDeletion$InProgressState;

  const factory ExampleDeletionState.error({Object? error}) = ExampleDeletion$ErrorState;

  const factory ExampleDeletionState.completed() = ExampleDeletion$CompletedState;
}

/// Deletes one example. Its state is independent of the creation form, so it is its own
/// controller (and feature).
final class ExampleDeletionController extends StateController<ExampleDeletionState>
    with DroppableControllerHandler {
  ExampleDeletionController({
    required this._repository,
    super.initialState = const ExampleDeletionState.initial(),
  });

  final IExampleDeletionRepository _repository;

  void delete(int id) => handle(() async {
    setState(const ExampleDeletionState.inProgress());
    await _repository.delete(id);
    setState(const ExampleDeletionState.completed());
  }, error: (error, stackTrace) async => setState(ExampleDeletionState.error(error: error)));
}
```

### `example_deletion_dialog.dart`

```dart
// file: example_deletion_dialog.dart
import 'package:control/control.dart';
import 'package:flutter/material.dart';

import 'example_deletion_controller.dart';

/// Confirmation dialog. It closes itself on completion and cannot be dismissed mid-flight.
class ExampleDeletionDialog extends StatelessWidget {
  const ExampleDeletionDialog({
    super.key,
    required this.controller,
    required this.exampleId,
    this.onSuccessfullyDelete,
  });

  final ExampleDeletionController controller;
  final int exampleId;

  /// Called before the dialog closes, so the parent screen can reload.
  final VoidCallback? onSuccessfullyDelete;

  @override
  Widget build(BuildContext context) {
    return StateConsumer<ExampleDeletionController, ExampleDeletionState>(
      controller: controller,
      listener: (context, controller, oldState, newState) {
        if (newState is ExampleDeletion$CompletedState) {
          onSuccessfullyDelete?.call();
          Navigator.pop(context);
        }
      },
      builder: (context, state, child) => PopScope(
        canPop: state is! ExampleDeletion$InProgressState,
        // Texts are literal only to keep the template self-contained: use `Localization.of`.
        child: AlertDialog(
          title: const Text('Delete'),
          content: const Text('Delete this item?'),
          actions: [
            TextButton(
              onPressed: state is ExampleDeletion$InProgressState
                  ? null
                  : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: state is ExampleDeletion$InProgressState
                  ? null
                  : () => controller.delete(exampleId),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
```

### `example_mutation_repositories.dart`

```dart
// file: example_mutation_repositories.dart
import 'example.dart';

/// Writes a record. Create versus update is decided here, not in the controller or the widget.
abstract interface class IExampleCreationRepository {
  /// Creates an example, or updates [existing] when it is given.
  Future<Example> save({required String title, required String content, Example? existing});
}

/// Deletes a record.
abstract interface class IExampleDeletionRepository {
  /// Deletes the example with [id].
  Future<void> delete(int id);
}
```

### `local_pagination_util.dart`

```dart
// file: local_pagination_util.dart
/// Infers whether another page exists from page fullness: a full page means probably yes, a short
/// page means the end. No server `total` is needed.
class LocalPaginationUtil {
  /// Creates the util.
  const LocalPaginationUtil();

  /// The next page to request: [page] + 1 after a full page, [page] after a short one.
  int checkIsListHasMorePageInt({
    required List<Object?> list,
    required int page,
    required int limitInPage,
  }) => list.length >= limitInPage ? page + 1 : page;

  /// Whether another page probably exists.
  bool checkIsListHasMorePageBool({required List<Object?> list, required int limitInPage}) =>
      list.length >= limitInPage;
}
```

### `product.dart`

```dart
// file: product.dart
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
```

### `products_controller.dart`

```dart
// file: products_controller.dart
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
```

### `products_data_controller.dart`

```dart
// file: products_data_controller.dart
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
```

### `products_list_widget.dart`

```dart
// file: products_list_widget.dart
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
```

### `products_repository.dart`

```dart
// file: products_repository.dart
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
```
