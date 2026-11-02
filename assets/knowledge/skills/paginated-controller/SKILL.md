---
name: paginated-controller
description: "Canonical paged-list controller: cursor in the state, load and paginate on one Sequential handler, scroll trigger in the widget."
when_to_use: "When a list loads page by page, infinite scroll, or a paginator is reviewed or added."
version: "2.0"
---

# Paginated controllers

Every paged list follows one shape. Copy it rather than inventing a variant: the differences
between hand-rolled paginators are where the silent bugs live.

## Rules

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

## Template

`products_controller.dart` (state, `load`, `paginate`), `products_repository.dart` (returns the page
and the server total as a record, `typedef ProductsPage = (List<Product> products, int total)`),
`local_pagination_util.dart`, `product.dart`, `products_data_controller.dart`,
`products_list_widget.dart`. `paginate`'s `hasMore` guard is what makes the repeated firing of a
bottom-of-list scroll notification safe.

## Convenience getters on the state

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

## Triggering `paginate` from the widget

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

## Non-paginated lists

An endpoint that truly returns one fixed or capped list (a small summary feed, a hard top-N with no
page controls) does not use this pattern: fetch it in one `load()` and render it, with no
`paginate()`. When in doubt, add pagination; most list endpoints accept `page` / `page_size`.

## Refinements, where the screen earns them

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
